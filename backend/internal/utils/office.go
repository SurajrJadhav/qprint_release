package utils

import (
	"archive/zip"
	"bytes"
	"encoding/binary"
	"errors"
	"io"
	"regexp"
	"strconv"
	"strings"

	"github.com/richardlehane/mscfb"
	"github.com/richardlehane/msoleps"
	"github.com/richardlehane/msoleps/types"
)

// ErrPageCountNotAvailable is returned when page/slide count cannot be determined for billing.
// Handlers should respond with PageCountNotAvailableMessage so the user converts to PDF and re-uploads.
var ErrPageCountNotAvailable = errors.New("page count not available")

// PageCountNotAvailableMessage is the user-facing message when page count cannot be determined.
const PageCountNotAvailableMessage = "Page count not available for this file. Please convert to PDF and upload."

// CountPPTXSlides returns the number of slides in a PPTX file (ZIP with ppt/slides/slideN.xml).
// Robust: PPTX is Office Open XML; slide count = number of slide XML parts.
func CountPPTXSlides(r io.Reader) (int, error) {
	b, err := io.ReadAll(r)
	if err != nil {
		return 0, err
	}
	zr, err := zip.NewReader(bytes.NewReader(b), int64(len(b)))
	if err != nil {
		return 0, err
	}
	var count int
	for _, f := range zr.File {
		name := strings.ToLower(f.Name)
		if strings.HasPrefix(name, "ppt/slides/slide") && strings.HasSuffix(name, ".xml") {
			count++
		}
	}
	if count == 0 {
		return 0, ErrPageCountNotAvailable
	}
	return count, nil
}

// CountDOCXPages returns the number of pages in a DOCX file.
// 1) Tries docProps/app.xml Extended File Properties <Pages> (set by Word when document is opened/saved).
// 2) Fallback: counts explicit page breaks and lastRenderedPageBreak in word/document.xml.
// Minimum returned is 1.
func CountDOCXPages(r io.Reader) (int, error) {
	b, err := io.ReadAll(r)
	if err != nil {
		return 0, err
	}
	zr, err := zip.NewReader(bytes.NewReader(b), int64(len(b)))
	if err != nil {
		return 0, err
	}
	// 1) Try docProps/app.xml for <Pages> (Extended File Properties)
	for _, f := range zr.File {
		if !strings.EqualFold(f.Name, "docProps/app.xml") {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			break
		}
		appXML, err := io.ReadAll(rc)
		rc.Close()
		if err != nil {
			break
		}
		// <Pages>N</Pages> - may have namespace prefix on Pages
		re := regexp.MustCompile(`<[^:>\s]*:?Pages[^>]*>(\d+)</[^:>\s]*:?Pages>`)
		if m := re.FindSubmatch(appXML); len(m) >= 2 {
			if n, err := strconv.Atoi(string(m[1])); err == nil && n > 0 {
				return n, nil
			}
		}
		break
	}
	// 2) Fallback: count page breaks in word/document.xml
	var docXML []byte
	for _, f := range zr.File {
		if strings.EqualFold(f.Name, "word/document.xml") {
			rc, err := f.Open()
			if err != nil {
				return 0, ErrPageCountNotAvailable
			}
			docXML, _ = io.ReadAll(rc)
			rc.Close()
			break
		}
	}
	if len(docXML) == 0 {
		return 0, ErrPageCountNotAvailable
	}
	pageBreak := regexp.MustCompile(`<[^:>\s]+:br\s[^>]*(?:w:type|type)\s*=\s*["']page["'][^>]*/?>`)
	lastRendered := regexp.MustCompile(`<[^:>\s]*:?lastRenderedPageBreak[^>]*/?>`)
	pages := 1 + len(pageBreak.FindAll(docXML, -1)) + len(lastRendered.FindAll(docXML, -1))
	if pages < 1 {
		pages = 1
	}
	return pages, nil
}

// CountDOCPages returns the number of pages in a legacy .doc (binary Word 97-2003) file.
// Reads the OLE SummaryInformation stream (PIDSI_PAGECOUNT). If missing or invalid, returns 1.
func CountDOCPages(r io.Reader) (int, error) {
	ra, ok := r.(io.ReaderAt)
	if !ok {
		b, err := io.ReadAll(r)
		if err != nil {
			return 0, err
		}
		ra = bytes.NewReader(b)
	}
	doc, err := mscfb.New(ra)
	if err != nil {
		return 0, err
	}
	props := msoleps.New()
	for entry, err := doc.Next(); err == nil; entry, err = doc.Next() {
		if entry == nil {
			break
		}
		if !msoleps.IsMSOLEPS(entry.Initial) {
			continue
		}
		if oerr := props.Reset(doc); oerr != nil {
			continue
		}
		for _, prop := range props.Property {
			if prop.Name != "Page Count" {
				continue
			}
			if i4, ok := prop.T.(types.I4); ok {
				n := int(i4)
				if n > 0 {
					return n, nil
				}
				break
			}
		}
		break
	}
	return 0, ErrPageCountNotAvailable
}

// PPT record type constants (MS-PPT binary format)
const (
	pptRecordHeaderSize    = 8
	pptRecordTypeDocument  = 0x03E8
	pptRecordTypeSlide     = 0x03EE
	pptRecordTypeSlideListWithText = 0x0FF0
	pptRecordTypeSlidePersistAtom  = 0x03F3
	pptRecordTypeUserEditAtom      = 0x0FF5
	pptRecordTypePersistDirectoryAtom = 0x1772
)

// CountPPTSlides returns the number of slides in a legacy .ppt (binary) file.
// Parses OLE container and PPT record stream to count SlidePersistAtom records.
func CountPPTSlides(r io.Reader) (int, error) {
	ra, ok := r.(io.ReaderAt)
	if !ok {
		b, err := io.ReadAll(r)
		if err != nil {
			return 0, err
		}
		ra = bytes.NewReader(b)
	}
	doc, err := mscfb.New(ra)
	if err != nil {
		return 0, err
	}
	var pptStream *mscfb.File
	for _, f := range doc.File {
		if f.Name == "PowerPoint Document" {
			pptStream = f
			break
		}
	}
	if pptStream == nil {
		return 0, errors.New("not a valid .ppt file: missing PowerPoint Document stream")
	}
	// Get Current User for persist directory offset (last UserEditAtom)
	var currentUser *mscfb.File
	for _, f := range doc.File {
		if f.Name == "Current User" {
			currentUser = f
			break
		}
	}
	if currentUser == nil {
		return 0, errors.New("not a valid .ppt file: missing Current User stream")
	}
	// Read Current User to get last edit position -> persist directory offset
	cuBuf, err := io.ReadAll(currentUser)
	if err != nil || len(cuBuf) < 20 {
		return 0, err
	}
	// Offset 16: lastEditPosition (uint32 LE), then follow chain; offset 12 in UserEditAtom: persistDirectoryOffset
	lastEdit := binary.LittleEndian.Uint32(cuBuf[16:20])
	// Read PowerPoint Document from lastEdit to get UserEditAtom, then persist directory
	persistOffset := int64(lastEdit)
	header := make([]byte, pptRecordHeaderSize)
	_, err = pptStream.ReadAt(header, persistOffset)
	if err != nil {
		return 0, err
	}
	recType := binary.LittleEndian.Uint16(header[2:4])
	recLen := binary.LittleEndian.Uint32(header[4:8])
	if recType != pptRecordTypeUserEditAtom {
		return 0, ErrPageCountNotAvailable
	}
	userEditData := make([]byte, recLen)
	_, _ = pptStream.ReadAt(userEditData, persistOffset+pptRecordHeaderSize)
	if len(userEditData) < 16 {
		return 0, ErrPageCountNotAvailable
	}
	persistDirOffset := int64(binary.LittleEndian.Uint32(userEditData[12:16]))
	// Read PersistDirectoryAtom to get docPersistId -> DocumentContainer offset
	_, err = pptStream.ReadAt(header, persistDirOffset)
	if err != nil {
		return 0, ErrPageCountNotAvailable
	}
	recType = binary.LittleEndian.Uint16(header[2:4])
	recLen = binary.LittleEndian.Uint32(header[4:8])
	if recType != pptRecordTypePersistDirectoryAtom {
		return 0, ErrPageCountNotAvailable
	}
	persistData := make([]byte, recLen)
	_, _ = pptStream.ReadAt(persistData, persistDirOffset+pptRecordHeaderSize)
	// Parse PersistDirectoryAtom: each entry is (persist uint32: low 20 bits = persistID, next 12 = cPersist), then cPersist*4 bytes of offsets
	persistDirEntries := make(map[uint32]int64)
	for j := 0; j+4 <= len(persistData); {
		persist := binary.LittleEndian.Uint32(persistData[j : j+4])
		persistID := persist & 0x000FFFFF
		cPersist := (persist >> 20) & 0xFFF
		j += 4
		if j+4*int(cPersist) > len(persistData) {
			break
		}
		for k := 0; k < int(cPersist); k++ {
			offset := binary.LittleEndian.Uint32(persistData[j : j+4])
			persistDirEntries[persistID+uint32(k)] = int64(offset)
			j += 4
		}
	}
	// Document persist ID ref is at UserEditAtom offset 16
	if len(userEditData) < 20 {
		return 0, ErrPageCountNotAvailable
	}
	docPersistIDRef := binary.LittleEndian.Uint32(userEditData[16:20])
	docOffset, ok := persistDirEntries[docPersistIDRef]
	if !ok {
		return 0, ErrPageCountNotAvailable
	}
	// Skip Document container header and records until SlideListWithText (0x0FF0)
	// Document: skip 48 bytes then look for SlideListWithText
	offset := docOffset + pptRecordHeaderSize
	const slideSkipInitial = 48
	offset += slideSkipInitial
	for {
		_, err = pptStream.ReadAt(header, offset)
		if err != nil {
			return 0, ErrPageCountNotAvailable
		}
		recType := binary.LittleEndian.Uint16(header[2:4])
		recLen := binary.LittleEndian.Uint32(header[4:8])
		if recType == pptRecordTypeSlideListWithText {
			// Count SlidePersistAtom (0x03F3) inside this record
			data := make([]byte, recLen)
			_, _ = pptStream.ReadAt(data, offset+pptRecordHeaderSize)
			var count int
			pos := 0
			for pos+pptRecordHeaderSize <= len(data) {
				rType := binary.LittleEndian.Uint16(data[pos+2 : pos+4])
				rLen := binary.LittleEndian.Uint32(data[pos+4 : pos+8])
				if rType == pptRecordTypeSlidePersistAtom {
					count++
				}
				pos += pptRecordHeaderSize + int(rLen)
			}
			if count > 0 {
				return count, nil
			}
			return 0, ErrPageCountNotAvailable
		}
		offset += pptRecordHeaderSize + int64(recLen)
		if offset > docOffset+1<<20 {
			return 0, ErrPageCountNotAvailable
		}
	}
}
