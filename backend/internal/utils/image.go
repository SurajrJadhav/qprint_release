package utils

import (
	"bytes"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"strings"
)

// ValidateImageBytes decodes the image to ensure it is not corrupted.
// ext should be .png, .jpg, or .jpeg. Returns nil for non-image exts or valid images.
func ValidateImageBytes(data []byte, ext string) error {
	ext = strings.ToLower(ext)
	if ext != ".png" && ext != ".jpg" && ext != ".jpeg" {
		return nil
	}
	_, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("image appears corrupted or invalid; please use a valid %s file", strings.TrimPrefix(ext, "."))
	}
	return nil
}
