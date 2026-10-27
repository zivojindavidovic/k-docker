-- Lokalne izmene office_master posle uvoza dump-a (scripts/db-init.sh).
-- Idempotentno: moze da se pusti vise puta.
USE `office_master`;

-- Licence pokazuju na lokalne license servere (ime servisa u Docker mrezi).
--   ID 1 -> k-license-1-db / office_licenca
--   ID 3 -> k-license-2-db / office_licenca3
UPDATE `office_license`
   SET `DBHost` = 'k-license-1-db', `DataBaseUser` = 'root', `DataBasePassword` = '', `DBTrue` = 1
 WHERE `ID` = 1;
UPDATE `office_license`
   SET `DBHost` = 'k-license-2-db', `DataBaseUser` = 'root', `DataBasePassword` = '', `DBTrue` = 1
 WHERE `ID` = 3;

-- Test korisnici (lozinke su u tenant bazama, vidi tenant-local.sql; svima je 'password'):
--   developer-1@paragraf.rs  licence 1 i 3, ista lozinka        -> izbor licence
--   developer-2@paragraf.rs  licence 1 i 3, razlicite lozinke   -> automatski licenca 1
--   developer-3@paragraf.rs  samo licenca 1                     -> prijava bez izbora
--   developer-4@paragraf.rs  licenca 1 + licenca 3 (arhiviran)  -> izbor: 1 prohodna, 3 siva
--   developer-5@paragraf.rs  licenca 1, suspendovan 7 dana      -> odbijen (user_suspended)
--   developer-6@paragraf.rs  licenca 1, userAcitve = 0          -> odbijen (account_inactive)
--   developer-7@paragraf.rs  licenca 1, email nije potvrdjen    -> odbijen (email_not_verified)
--   developer-8@paragraf.rs  licenca 1, uslovi nisu prihvaceni  -> prijava + accept_terms
DELETE FROM `office_users` WHERE `userName` LIKE 'developer-%@paragraf.rs';

INSERT INTO `office_users` (`licenseID`, `userName`, `userAcitve`, `emailVerificationCode`, `lastUpdateTime`) VALUES
  (1, 'developer-1@paragraf.rs', 1, NULL, NOW()),
  (3, 'developer-1@paragraf.rs', 1, NULL, NOW()),
  (1, 'developer-2@paragraf.rs', 1, NULL, NOW()),
  (3, 'developer-2@paragraf.rs', 1, NULL, NOW()),
  (1, 'developer-3@paragraf.rs', 1, NULL, NOW()),
  (1, 'developer-4@paragraf.rs', 1, NULL, NOW()),
  (3, 'developer-4@paragraf.rs', 1, NULL, NOW()),
  (1, 'developer-5@paragraf.rs', 1, NULL, NOW()),
  (1, 'developer-6@paragraf.rs', 0, NULL, NOW()),
  (1, 'developer-7@paragraf.rs', 1, 'lokalni-kod-za-potvrdu', NOW()),
  (1, 'developer-8@paragraf.rs', 1, NULL, NOW());

-- Slobodna licenca za probu registracije: ID 4, RegistrationDate = NULL.
--   appCode KAUT-TEST-REGI-0004 -> k-license-2-db / office_licenca4 (prazna baza iz sablona)
-- Ponovni `task db-init` je vraca u slobodno stanje (brise i probnu registraciju).
DELETE FROM `office_users` WHERE `licenseID` = 4;

INSERT INTO `office_license`
  (`ID`, `GeneratedDate`, `licenseType`, `appCode`, `RegistrationDate`, `ExpirationDate`, `StopDate`, `NumberOfUsers`,
   `StorageLimit`, `DBTrue`, `DataBaseName`, `DataBaseUser`, `DataBasePassword`, `DataBaseVersion`, `LastLoginDate`,
   `LastDBBackupTime`, `LastDBBackupName`, `NotificationTime`, `DBHost`, `TimeAvailabilityGroup`, `login_2fa`)
SELECT 4, `GeneratedDate`, `licenseType`, 'KAUT-TEST-REGI-0004', NULL, `ExpirationDate`, `StopDate`, `NumberOfUsers`,
       `StorageLimit`, 1, 'office_licenca4', 'root', '', `DataBaseVersion`, NULL,
       NULL, NULL, `NotificationTime`, 'k-license-2-db', NULL, 0
  FROM `office_license` WHERE `ID` = 3
ON DUPLICATE KEY UPDATE
  `appCode` = 'KAUT-TEST-REGI-0004', `RegistrationDate` = NULL, `LastLoginDate` = NULL, `DBTrue` = 1,
  `DataBaseName` = 'office_licenca4', `DataBaseUser` = 'root', `DataBasePassword` = '', `DBHost` = 'k-license-2-db',
  `TimeAvailabilityGroup` = NULL, `login_2fa` = 0;
