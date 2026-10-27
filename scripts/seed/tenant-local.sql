-- Lokalni test podaci u tenant (licence) bazi posle uvoza dump-a.
-- Pre ovog fajla db-init.sh postavlja:
--   USE <baza>; SET @company = '<naziv firme>'; SET @license = <ID licence>;
-- Idempotentno: moze da se pusti vise puta.

-- Lozinke (bcrypt): 'password' i 'drugalozinka'.
SET @pass_default = '$2y$10$yhd9VvUPh31Knlo70EbpSeqo4t449KXVj/Li3YlyuTBGev7fWLVB2';
SET @pass_other   = '$2y$10$dRUn3qTG0ItyDvqDIEj1..YmGZZK29iOfiSaX894lnEaQA6h8zECO';

-- Firma licence: naziv se prikazuje pri izboru licence (company.localCompany = 1).
-- Sablon tenant baze ima samo company ID 1, pa se ona preimenuje.
UPDATE `company` SET `companyName` = @company WHERE `ID` = 1;

-- Brisanje prethodnih test korisnika, redom zbog stranih kljuceva:
-- login_log -> users -> employee (zaposleni test korisnika imaju defaultEmail = username).
DELETE `l`
  FROM `login_log` `l`
  JOIN `users` `u` ON `u`.`id` = `l`.`userID`
 WHERE `u`.`username` LIKE 'developer-%@paragraf.rs';

DELETE FROM `users` WHERE `username` LIKE 'developer-%@paragraf.rs';

DELETE FROM `employee` WHERE `defaultEmail` LIKE 'developer-%@paragraf.rs';

-- developer-1: ista lozinka na obe licence; SADMIN na licenci 1, USER na licenci 3.
INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
VALUES ('Developer', '1', 'developer-1@paragraf.rs', NOW());
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
VALUES (LAST_INSERT_ID(), 'developer-1@paragraf.rs', @pass_default, b'1', IF(@license = 1, 'SADMIN', 'USER'), b'0', 1);

-- developer-2: 'password' samo na licenci 1, 'drugalozinka' na licenci 3.
INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
VALUES ('Developer', '2', 'developer-2@paragraf.rs', NOW());
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
VALUES (LAST_INSERT_ID(), 'developer-2@paragraf.rs', IF(@license = 1, @pass_default, @pass_other), b'1', 'USER', b'0', 1);

-- developer-3: samo na licenci 1.
INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
SELECT 'Developer', '3', 'developer-3@paragraf.rs', NOW() FROM DUAL WHERE @license = 1;
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
SELECT LAST_INSERT_ID(), 'developer-3@paragraf.rs', @pass_default, b'1', 'ADMIN', b'0', 1 FROM DUAL WHERE @license = 1;

-- developer-4: aktivan na licenci 1, arhiviran na licenci 3 (siva licenca pri izboru).
INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
VALUES ('Developer', '4', 'developer-4@paragraf.rs', NOW());
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
VALUES (LAST_INSERT_ID(), 'developer-4@paragraf.rs', @pass_default, b'1', 'USER', IF(@license = 3, b'1', b'0'), 1);

-- developer-5 do developer-8 samo na licenci 1 (pravila pristupa).
-- developer-5: suspendovan 7 dana.
INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
SELECT 'Developer', '5', 'developer-5@paragraf.rs', NOW() FROM DUAL WHERE @license = 1;
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`, `suspendedUntil`)
SELECT LAST_INSERT_ID(), 'developer-5@paragraf.rs', @pass_default, b'1', 'USER', b'0', 1, CURDATE() + INTERVAL 7 DAY FROM DUAL WHERE @license = 1;

-- developer-6: nalog na licenci nije aktivan (office_users.userAcitve = 0 u master-local.sql).
INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
SELECT 'Developer', '6', 'developer-6@paragraf.rs', NOW() FROM DUAL WHERE @license = 1;
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
SELECT LAST_INSERT_ID(), 'developer-6@paragraf.rs', @pass_default, b'1', 'USER', b'0', 1 FROM DUAL WHERE @license = 1;

-- developer-7: email nije potvrdjen (office_users.emailVerificationCode u master-local.sql).
INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
SELECT 'Developer', '7', 'developer-7@paragraf.rs', NOW() FROM DUAL WHERE @license = 1;
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
SELECT LAST_INSERT_ID(), 'developer-7@paragraf.rs', @pass_default, b'1', 'USER', b'0', 1 FROM DUAL WHERE @license = 1;

-- developer-8: uslovi nisu prihvaceni.
INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
SELECT 'Developer', '8', 'developer-8@paragraf.rs', NOW() FROM DUAL WHERE @license = 1;
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
SELECT LAST_INSERT_ID(), 'developer-8@paragraf.rs', @pass_default, b'1', 'USER', b'0', 0 FROM DUAL WHERE @license = 1;
