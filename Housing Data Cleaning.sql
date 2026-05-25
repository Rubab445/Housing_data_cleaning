
-- Nashville Housing Data Cleaning Script
-- Steps: Load Data > Remove Duplicates > Standardize > Fix Nulls > Drop Columns

-- STEP 0: LOAD RAW DATA INTO STAGING TABLE


-- NOTE: SET GLOBAL local_infile must run BEFORE the LOAD DATA command
SET GLOBAL local_infile = 1;

-- Create a staging table to hold raw CSV data (all columns as TEXT to avoid import errors)
CREATE TABLE NashvilleHousing_Staging (
    UniqueID TEXT, ParcelID TEXT, LandUse TEXT, PropertyAddress TEXT,
    SaleDate TEXT, SalePrice TEXT, LegalReference TEXT, SoldAsVacant TEXT,
    OwnerName TEXT, OwnerAddress TEXT, Acreage TEXT, TaxDistrict TEXT,
    LandValue TEXT, BuildingValue TEXT, TotalValue TEXT, YearBuilt TEXT,
    Bedrooms TEXT, FullBath TEXT, HalfBath TEXT
);

LOAD DATA LOCAL INFILE '/your/local/path/Nashville Housing.csv'
INTO TABLE NashvilleHousing_Staging
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS;

SELECT * FROM NashvilleHousing_Staging;


-- STEP 1: CREATE WORKING STAGING TABLE


-- Copy raw data into a working table so the original import is never modified
CREATE TABLE nashvillehousing_staging1 LIKE NashvilleHousing_Staging;

INSERT INTO nashvillehousing_staging1
SELECT * FROM NashvilleHousing_Staging;

-- STEP 2: REMOVE DUPLICATES


-- Identify duplicates by assigning row numbers within groups of identical key columns
-- Any row with row_num > 1 is a duplicate
WITH housing_cte AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY ParcelID, LandUse, PropertyAddress, SaleDate, SalePrice,
            LegalReference, SoldAsVacant, OwnerName, OwnerAddress, Acreage, TaxDistrict,
            LandValue, BuildingValue, TotalValue, Bedrooms, YearBuilt, FullBath, HalfBath
            ORDER BY UniqueID
        ) AS row_num
    FROM nashvillehousing_staging1
)
SELECT * FROM housing_cte WHERE row_num > 1;

-- Create a second staging table with row_num column so we can DELETE duplicates
-- (MySQL doesn't allow DELETE directly on a CTE)
CREATE TABLE housing_staging2 (
    UniqueID TEXT, ParcelID TEXT, LandUse TEXT, PropertyAddress TEXT,
    SaleDate TEXT, SalePrice TEXT, LegalReference TEXT, SoldAsVacant TEXT,
    OwnerName TEXT, OwnerAddress TEXT, Acreage TEXT, TaxDistrict TEXT,
    LandValue TEXT, BuildingValue TEXT, TotalValue TEXT, YearBuilt TEXT,
    Bedrooms TEXT, FullBath TEXT, HalfBath TEXT,
    row_num INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO housing_staging2
SELECT *,
    ROW_NUMBER() OVER (
        PARTITION BY ParcelID, LandUse, PropertyAddress, SaleDate, SalePrice,
        LegalReference, SoldAsVacant, OwnerName, OwnerAddress, Acreage, TaxDistrict,
        LandValue, BuildingValue, TotalValue, Bedrooms, YearBuilt, FullBath, HalfBath
        ORDER BY UniqueID
    ) AS row_num
FROM nashvillehousing_staging1;

-- Delete all duplicate rows (keep only row_num = 1 per group)
DELETE FROM housing_staging2 WHERE row_num > 1;


-- STEP 3: STANDARDIZE DATA

-- Convert UniqueID to INT now that all values are confirmed clean
ALTER TABLE housing_staging2
MODIFY UniqueID INT;

-- Consolidate LandUse variations into consistent labels
UPDATE housing_staging2
SET LandUse = 'VACANT RESIDENTIAL LAND'
WHERE LandUse LIKE 'VACANT RES%';

UPDATE housing_staging2
SET LandUse = 'GREENBELT/RES'
WHERE LandUse LIKE '%GREENBELT/%';

-- Normalize SoldAsVacant: standardize shorthand 'Y'/'N' entries to full 'Yes'/'No'
UPDATE housing_staging2 SET SoldAsVacant = 'No'  WHERE SoldAsVacant LIKE 'N%';
UPDATE housing_staging2 SET SoldAsVacant = 'Yes' WHERE SoldAsVacant LIKE 'Y%';

-- Clean SalePrice: remove whitespace, commas, and dollar signs for numeric conversion later
UPDATE housing_staging2
SET SalePrice = REPLACE(REPLACE(TRIM(SalePrice), ',', ''), '$', '');

-- Split PropertyAddress into Street and City columns
ALTER TABLE housing_staging2
ADD PropertyStreet VARCHAR(255),
ADD PropertyCity  VARCHAR(255);

UPDATE housing_staging2
SET PropertyStreet = TRIM(SUBSTRING_INDEX(PropertyAddress, ',', 1)),
    PropertyCity   = TRIM(SUBSTRING_INDEX(PropertyAddress, ',', -1));

-- Split OwnerAddress into Street, City, and State columns
ALTER TABLE housing_staging2
ADD OwnerStreet VARCHAR(255),
ADD OwnerCity   VARCHAR(255),
ADD OwnerState  VARCHAR(255);

UPDATE housing_staging2
SET OwnerStreet = TRIM(SUBSTRING_INDEX(OwnerAddress, ',', 1)),
    OwnerCity   = TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(OwnerAddress, ',', 2), ',', -1)),
    OwnerState  = TRIM(SUBSTRING_INDEX(OwnerAddress, ',', -1));

-- Convert SaleDate from text (e.g. 'January 1, 2021') to proper DATE type
UPDATE housing_staging2
SET SaleDate = STR_TO_DATE(SaleDate, '%M %e, %Y');

ALTER TABLE housing_staging2
MODIFY COLUMN SaleDate DATE;

-- Cast numeric columns to their correct data types
ALTER TABLE housing_staging2
MODIFY COLUMN SalePrice      INT,
MODIFY COLUMN Acreage        DECIMAL(10,2),
MODIFY COLUMN YearBuilt      INT,
MODIFY COLUMN Bedrooms       INT,
MODIFY COLUMN FullBath       INT,
MODIFY COLUMN HalfBath       INT,
MODIFY COLUMN LandValue      INT,
MODIFY COLUMN BuildingValue  INT,
MODIFY COLUMN TotalValue     INT;


-- STEP 4: HANDLE NULL / BLANK VALUES


-- Normalize empty strings to NULL before casting (avoids type conversion errors)
UPDATE housing_staging2 SET SalePrice     = NULL WHERE SalePrice     = '';
UPDATE housing_staging2 SET YearBuilt     = NULL WHERE YearBuilt     = '';
UPDATE housing_staging2 SET Bedrooms      = NULL WHERE Bedrooms      = '';
UPDATE housing_staging2 SET FullBath      = NULL WHERE FullBath      = '';
UPDATE housing_staging2 SET HalfBath      = NULL WHERE HalfBath      = '';
UPDATE housing_staging2 SET LandValue     = NULL WHERE LandValue     = '';
UPDATE housing_staging2 SET BuildingValue = NULL WHERE BuildingValue = '';
UPDATE housing_staging2 SET TotalValue    = NULL WHERE TotalValue    = '';

-- Attempt to fill NULL Acreage by matching on ParcelID from another row with the same parcel
-- (In this dataset, the self-join returned no results, so no update was performed)
SELECT t1.ParcelID, t1.Acreage, t2.Acreage
FROM housing_staging2 AS t1
JOIN housing_staging2 AS t2
    ON t1.ParcelID = t2.ParcelID
    AND t1.UniqueID <> t2.UniqueID
WHERE t1.Acreage IS NULL
AND t2.Acreage IS NOT NULL;


-- STEP 5: DROP UNNEEDED COLUMNS

-- Remove original address columns now that Street/City/State splits are in place
-- Also drop row_num since deduplication is complete
ALTER TABLE housing_staging2
DROP COLUMN PropertyAddress,
DROP COLUMN OwnerAddress,
DROP COLUMN row_num;

SELECT * FROM housing_staging2;