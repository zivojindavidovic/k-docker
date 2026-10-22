-- Lokalne izmene office_master posle uvoza dump-a (scripts/db-seed.sh).
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
--   multi@k-auth.local           licence 1 i 3, ista lozinka        -> izbor licence
--   multi.razlicita@k-auth.local licence 1 i 3, razlicite lozinke   -> automatski licenca 1
--   single@k-auth.local          samo licenca 1                     -> prijava bez izbora
--   siva@k-auth.local            licenca 1 + licenca 3 (arhiviran)  -> izbor: 1 prohodna, 3 siva
--   suspendovan@k-auth.local     licenca 1, suspendovan 7 dana      -> odbijen (user_suspended)
--   neaktivan@k-auth.local       licenca 1, userAcitve = 0          -> odbijen (account_inactive)
--   nepotvrdjen@k-auth.local     licenca 1, email nije potvrdjen    -> odbijen (email_not_verified)
--   uslovi@k-auth.local          licenca 1, uslovi nisu prihvaceni  -> prijava + accept_terms
DELETE FROM `office_users`
 WHERE `userName` IN ('multi@k-auth.local', 'multi.razlicita@k-auth.local', 'single@k-auth.local',
                     'siva@k-auth.local', 'suspendovan@k-auth.local', 'neaktivan@k-auth.local',
                     'nepotvrdjen@k-auth.local', 'uslovi@k-auth.local');

INSERT INTO `office_users` (`licenseID`, `userName`, `userAcitve`, `emailVerificationCode`, `lastUpdateTime`) VALUES
  (1, 'multi@k-auth.local', 1, NULL, NOW()),
  (3, 'multi@k-auth.local', 1, NULL, NOW()),
  (1, 'multi.razlicita@k-auth.local', 1, NULL, NOW()),
  (3, 'multi.razlicita@k-auth.local', 1, NULL, NOW()),
  (1, 'single@k-auth.local', 1, NULL, NOW()),
  (1, 'siva@k-auth.local', 1, NULL, NOW()),
  (3, 'siva@k-auth.local', 1, NULL, NOW()),
  (1, 'suspendovan@k-auth.local', 1, NULL, NOW()),
  (1, 'neaktivan@k-auth.local', 0, NULL, NOW()),
  (1, 'nepotvrdjen@k-auth.local', 1, 'lokalni-kod-za-potvrdu', NOW()),
  (1, 'uslovi@k-auth.local', 1, NULL, NOW());

-- Slobodna licenca za probu registracije: ID 4, RegistrationDate = NULL.
--   appCode KAUT-TEST-REGI-0004 -> k-license-2-db / office_licenca4 (prazna baza iz sablona)
-- Ponovni `task db-seed` je vraca u slobodno stanje (brise i probnu registraciju).
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
