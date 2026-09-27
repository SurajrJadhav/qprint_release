package utils

import (
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"github.com/pdfcpu/pdfcpu/pkg/api"
)

// CountPDFPages returns the number of pages in a PDF file
// Accepts either a file path (string) or an io.Reader
func CountPDFPages(filePathOrReader interface{}) (int, error) {
	switch v := filePathOrReader.(type) {
	case string:
		// If it's a string, treat it as a file path
		pageCount, err := api.PageCountFile(v)
		if err != nil {
			return 0, fmt.Errorf("failed to count PDF pages: %w", err)
		}
		return pageCount, nil
	case io.Reader:
		// If it's an io.Reader, we need to write it to a temp file first
		tmpFile, err := os.CreateTemp("", "pdf-*.pdf")
		if err != nil {
			return 0, fmt.Errorf("failed to create temp file: %w", err)
		}
		defer os.Remove(tmpFile.Name())
		defer tmpFile.Close()

		if _, err := io.Copy(tmpFile, v); err != nil {
			return 0, fmt.Errorf("failed to write to temp file: %w", err)
		}
		tmpFile.Close()

		pageCount, err := api.PageCountFile(tmpFile.Name())
		if err != nil {
			return 0, fmt.Errorf("failed to count PDF pages: %w", err)
		}
		return pageCount, nil
	default:
		return 0, fmt.Errorf("unsupported type for CountPDFPages")
	}
}

// CountPDFPagesFromPath is a convenience function that explicitly takes a file path
func CountPDFPagesFromPath(filePath string) (int, error) {
	return CountPDFPages(filePath)
}

// CountPDFPagesFromReader is a convenience function that explicitly takes an io.Reader
func CountPDFPagesFromReader(reader io.Reader) (int, error) {
	return CountPDFPages(reader)
}

// GetCostPerPageBW returns the price per page for black & white from env COST_PER_PAGE_BW (default 1).
func GetCostPerPageBW() float64 {
	s := os.Getenv("COST_PER_PAGE_BW")
	if s == "" {
		return 1.0
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil || v < 0 {
		return 1.0
	}
	return v
}

// GetCostPerPageColor returns the price per page for colour from env COST_PER_PAGE_COLOR (default 10).
func GetCostPerPageColor() float64 {
	s := os.Getenv("COST_PER_PAGE_COLOR")
	if s == "" {
		return 10.0
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil || v < 0 {
		return 10.0
	}
	return v
}

// GetCostPerPageForMode returns the price per page for the given color_mode ("bw" or "color").
// Any value other than "color" (case-insensitive) is treated as black & white.
func GetCostPerPageForMode(colorMode string) float64 {
	if strings.EqualFold(colorMode, "color") {
		return GetCostPerPageColor()
	}
	return GetCostPerPageBW()
}

// CostParams holds inputs for cost calculation with optional shop overrides.
// When RateBW, RateColor are nil, platform env defaults are used.
// DoubleSidedFactor is only from shopkeeper (nil = no discount, i.e. 1.0).
type CostParams struct {
	Pages             int
	Copies            int
	ColorMode         string
	PrintMode         string
	RateBW            *float64 // nil = use COST_PER_PAGE_BW
	RateColor         *float64 // nil = use COST_PER_PAGE_COLOR
	DoubleSidedFactor *float64 // nil = no discount (1.0); set by shopkeeper, visible to customer
}

// CalculateCostFromParams computes total cost using platform or shop rates and shopkeeper-set double-sided factor.
func CalculateCostFromParams(p CostParams) float64 {
	var rate float64
	if strings.EqualFold(p.ColorMode, "color") {
		if p.RateColor != nil {
			rate = *p.RateColor
		} else {
			rate = GetCostPerPageColor()
		}
	} else {
		if p.RateBW != nil {
			rate = *p.RateBW
		} else {
			rate = GetCostPerPageBW()
		}
	}
	base := float64(p.Pages*p.Copies) * rate
	if !strings.EqualFold(p.PrintMode, "double") {
		return base
	}
	f := 1.0
	if p.DoubleSidedFactor != nil {
		f = *p.DoubleSidedFactor
	}
	return base * f
}

// CalculateCost calculates the total cost: pages × copies × cost per page (color_mode), with optional double-sided discount.
// colorMode is "bw" or "color"; printMode "double" applies DOUBLE_SIDED_PRICE_FACTOR (default 1.0).
// For queue orders with shop pricing, use CalculateCostFromParams with shop rates instead.
func CalculateCost(pages, copies int, colorMode, printMode string) float64 {
	return CalculateCostFromParams(CostParams{
		Pages: pages, Copies: copies, ColorMode: colorMode, PrintMode: printMode,
		RateBW: nil, RateColor: nil, DoubleSidedFactor: nil,
	})
}
