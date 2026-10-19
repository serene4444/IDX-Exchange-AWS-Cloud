-- Week 04, Lab 4.2: sanitize the imported rets_property table.
-- Run AFTER importing rets_property.sql and BEFORE any analysis query:
--   mysql -h <rds-endpoint> -u admin -p training_data < pii-cleanup.sql
--
-- This differs from the handbook's version in two places:
--   1. It also drops L_DisplayId (the MLS number shown to the public, which maps
--      straight back to the live listing) and L_Remarks (free-text agent remarks
--      that often contain names and phone numbers), plus LO1_OrganizationName
--      and ListAgentAOR (the agent's brokerage and association).
--   2. The dump already makes `id` an AUTO_INCREMENT PRIMARY KEY, so the handbook's
--      bare `ADD PRIMARY KEY (L_ListingID)` fails with "Multiple primary key defined".
--      The last step drops that key first.

-- 1. Drop every PII / identifying column (17 from the handbook + 4 extra).
ALTER TABLE rets_property
  DROP COLUMN LA1_UserFirstName, DROP COLUMN LA1_UserLastName,
  DROP COLUMN ListAgentFullName, DROP COLUMN CoListAgentFullName,
  DROP COLUMN ListAgentEmail, DROP COLUMN ListOfficeEmail,
  DROP COLUMN ListAgentDirectPhone, DROP COLUMN ListAgentOfficePhone,
  DROP COLUMN ListAgentKey, DROP COLUMN L_Address,
  DROP COLUMN L_AddressStreet, DROP COLUMN ParcelNumber,
  DROP COLUMN UniversalParcelId, DROP COLUMN TaxLot,
  DROP COLUMN LMD_MP_Latitude, DROP COLUMN LMD_MP_Longitude,
  DROP COLUMN L_Photos,
  DROP COLUMN L_DisplayId, DROP COLUMN L_Remarks,
  DROP COLUMN LO1_OrganizationName, DROP COLUMN ListAgentAOR;

-- 2. Replace the real MLS listing ID with a synthetic one (R100001, R100002, ...).
--    ORDER BY id makes the numbering deterministic.
ALTER TABLE rets_property ADD COLUMN training_id VARCHAR(20);

UPDATE rets_property t
JOIN (SELECT id, CONCAT('R', 100000 + ROW_NUMBER() OVER (ORDER BY id)) AS new_id
      FROM rets_property) r ON t.id = r.id
SET t.training_id = r.new_id;

ALTER TABLE rets_property DROP COLUMN L_ListingID;
ALTER TABLE rets_property CHANGE training_id L_ListingID VARCHAR(20) NOT NULL;

-- 3. Make the synthetic ID the primary key. `id` loses AUTO_INCREMENT first,
--    because MySQL won't drop the key an AUTO_INCREMENT column depends on.
ALTER TABLE rets_property
  MODIFY id INT NOT NULL,
  DROP PRIMARY KEY,
  ADD PRIMARY KEY (L_ListingID);

-- 4. Verify. Every query below should return 0 / no rows.
SELECT COUNT(*) AS pii_columns_remaining
FROM information_schema.columns
WHERE table_schema = DATABASE() AND table_name = 'rets_property'
  AND column_name IN ('LA1_UserFirstName','LA1_UserLastName','ListAgentFullName',
    'CoListAgentFullName','ListAgentEmail','ListOfficeEmail','ListAgentDirectPhone',
    'ListAgentOfficePhone','ListAgentKey','L_Address','L_AddressStreet','ParcelNumber',
    'UniversalParcelId','TaxLot','LMD_MP_Latitude','LMD_MP_Longitude','L_Photos',
    'L_DisplayId','L_Remarks','LO1_OrganizationName','ListAgentAOR');

SELECT COUNT(*) AS ids_not_synthetic
FROM rets_property WHERE L_ListingID NOT LIKE 'R1%';

-- 5. The aggregate check from the handbook.
SELECT L_City, COUNT(*), AVG(L_SystemPrice)
FROM rets_property
GROUP BY L_City
ORDER BY 2 DESC
LIMIT 10;
