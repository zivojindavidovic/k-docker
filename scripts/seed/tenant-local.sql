-- Lokalni test podaci u tenant (licence) bazi posle uvoza dump-a.
-- Pre ovog fajla db-seed.sh postavlja:
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
 WHERE `u`.`username` IN (
  'multi@k-auth.local', 'multi.razlicita@k-auth.local', 'single@k-auth.local',
  'siva@k-auth.local', 'suspendovan@k-auth.local', 'neaktivan@k-auth.local',
  'nepotvrdjen@k-auth.local', 'uslovi@k-auth.local');

DELETE FROM `users`
 WHERE `username` IN (
  'multi@k-auth.local', 'multi.razlicita@k-auth.local', 'single@k-auth.local',
  'siva@k-auth.local', 'suspendovan@k-auth.local', 'neaktivan@k-auth.local',
  'nepotvrdjen@k-auth.local', 'uslovi@k-auth.local');

DELETE FROM `employee`
 WHERE `defaultEmail` IN (
  'multi@k-auth.local', 'multi.razlicita@k-auth.local', 'single@k-auth.local',
  'siva@k-auth.local', 'suspendovan@k-auth.local', 'neaktivan@k-auth.local',
  'nepotvrdjen@k-auth.local', 'uslovi@k-auth.local');

-- multi@k-auth.local: ista lozinka na obe licence; SADMIN na licenci 1, USER na licenci 3.
INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
VALUES ('Multi', 'Licenca', 'multi@k-auth.local', NOW());
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
VALUES (LAST_INSERT_ID(), 'multi@k-auth.local', @pass_default, b'1', IF(@license = 1, 'SADMIN', 'USER'), b'0', 1);

-- multi.razlicita@k-auth.local: 'password' samo na licenci 1, 'drugalozinka' na licenci 3.
INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
VALUES ('Multi', 'Razlicita', 'multi.razlicita@k-auth.local', NOW());
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
VALUES (LAST_INSERT_ID(), 'multi.razlicita@k-auth.local', IF(@license = 1, @pass_default, @pass_other), b'1', 'USER', b'0', 1);

-- single@k-auth.local: samo na licenci 1.
INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
SELECT 'Single', 'Licenca', 'single@k-auth.local', NOW() FROM DUAL WHERE @license = 1;
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
SELECT LAST_INSERT_ID(), 'single@k-auth.local', @pass_default, b'1', 'ADMIN', b'0', 1 FROM DUAL WHERE @license = 1;

-- siva@k-auth.local: aktivan na licenci 1, arhiviran na licenci 3 (siva licenca pri izboru).
INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
VALUES ('Siva', 'Licenca', 'siva@k-auth.local', NOW());
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
VALUES (LAST_INSERT_ID(), 'siva@k-auth.local', @pass_default, b'1', 'USER', IF(@license = 3, b'1', b'0'), 1);

-- Ostali slucajevi samo na licenci 1 (pravila pristupa).
INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
SELECT 'Suspendovan', 'Korisnik', 'suspendovan@k-auth.local', NOW() FROM DUAL WHERE @license = 1;
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`, `suspendedUntil`)
SELECT LAST_INSERT_ID(), 'suspendovan@k-auth.local', @pass_default, b'1', 'USER', b'0', 1, CURDATE() + INTERVAL 7 DAY FROM DUAL WHERE @license = 1;

INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
SELECT 'Neaktivan', 'Korisnik', 'neaktivan@k-auth.local', NOW() FROM DUAL WHERE @license = 1;
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
SELECT LAST_INSERT_ID(), 'neaktivan@k-auth.local', @pass_default, b'1', 'USER', b'0', 1 FROM DUAL WHERE @license = 1;

INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
SELECT 'Nepotvrdjen', 'Korisnik', 'nepotvrdjen@k-auth.local', NOW() FROM DUAL WHERE @license = 1;
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
SELECT LAST_INSERT_ID(), 'nepotvrdjen@k-auth.local', @pass_default, b'1', 'USER', b'0', 1 FROM DUAL WHERE @license = 1;

INSERT INTO `employee` (`firstname`, `lastname`, `defaultEmail`, `create_date`)
SELECT 'Uslovi', 'Korisnik', 'uslovi@k-auth.local', NOW() FROM DUAL WHERE @license = 1;
INSERT INTO `users` (`FK_employee`, `username`, `password`, `enable`, `role`, `archived`, `accept_conditions`)
SELECT LAST_INSERT_ID(), 'uslovi@k-auth.local', @pass_default, b'1', 'USER', b'0', 0 FROM DUAL WHERE @license = 1;
