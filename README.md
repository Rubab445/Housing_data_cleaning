# Nashville Housing — Data Cleaning Project

## Overview

This project cleans a raw Nashville housing dataset using MySQL. The goal is to transform messy, inconsistently formatted CSV data into a clean, analysis-ready table by removing duplicates, standardizing values, fixing nulls, splitting address columns, and casting columns to the correct data types.

---

## Dataset

| Field | Details |
|---|---|
| **Source** | Nashville Housing CSV |
| **Tool** | MySQL |
| **Raw Table** | `NashvilleHousing_Staging` |
| **Clean Table** | `housing_staging2` |

### Columns

`UniqueID`, `ParcelID`, `LandUse`, `PropertyAddress`, `SaleDate`, `SalePrice`, `LegalReference`, `SoldAsVacant`, `OwnerName`, `OwnerAddress`, `Acreage`, `TaxDistrict`, `LandValue`, `BuildingValue`, `TotalValue`, `YearBuilt`, `Bedrooms`, `FullBath`, `HalfBath`

---

## Cleaning Steps

### 1. Load Raw Data
- Enabled `local_infile` to allow CSV import
- All columns imported as `TEXT` to prevent type mismatch errors during load
- Raw data preserved in `NashvilleHousing_Staging`; all work done on copies

### 2. Remove Duplicates
- Used `ROW_NUMBER() OVER (PARTITION BY ...)` across all key columns to flag duplicate rows
- Created `housing_staging2` with a `row_num` column (MySQL does not support `DELETE` on CTEs directly)
- Deleted all rows where `row_num > 1`

### 3. Standardize Data
- **LandUse** — consolidated variations like `VACANT RES*` → `VACANT RESIDENTIAL LAND` and `GREENBELT/*` → `GREENBELT/RES`
- **SoldAsVacant** — normalized shorthand `Y`/`N` entries to `Yes`/`No`
- **SalePrice** — stripped whitespace, commas, and dollar signs
- **PropertyAddress** — split into `PropertyStreet` and `PropertyCity`
- **OwnerAddress** — split into `OwnerStreet`, `OwnerCity`, and `OwnerState`
- **SaleDate** — converted from text format (`Month DD, YYYY`) to `DATE` type using `STR_TO_DATE`
- **Data types** — cast `SalePrice`, `Acreage`, `YearBuilt`, `Bedrooms`, `FullBath`, `HalfBath`, `LandValue`, `BuildingValue`, `TotalValue` to their correct numeric types

### 4. Handle Nulls & Blanks
- Replaced empty strings (`''`) with `NULL` across all numeric columns before type casting
- Attempted to fill `NULL` Acreage values by self-joining on `ParcelID` — no matching rows found in this dataset

### 5. Drop Unneeded Columns
- Dropped `PropertyAddress` and `OwnerAddress` (replaced by split columns)
- Dropped `row_num` (only needed for deduplication)

---

## File Structure

```
├── nashville_housing_cleaning.sql   # Full cleaning script
└── README_NashvilleHousing.md       # This file
```

---

## How to Run

1. Open MySQL Workbench (or any MySQL client)
2. Run `SET GLOBAL local_infile = 1;` first — required before the CSV import
3. Update the file path in the `LOAD DATA LOCAL INFILE` statement to match your local CSV location
4. Execute the full script
5. Query `SELECT * FROM housing_staging2;` to view the cleaned data
