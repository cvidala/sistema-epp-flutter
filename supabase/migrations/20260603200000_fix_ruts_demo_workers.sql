-- Corrige RUTs inválidos de trabajadores demo (Emi: "1234", Fran: "654").
-- RUTs generados con dígito verificador válido para uso exclusivo de demo.

UPDATE trabajadores SET rut = '14.567.890-0' WHERE nombre = 'Emi'  AND rut = '1234';
UPDATE trabajadores SET rut = '13.456.789-9' WHERE nombre = 'Fran' AND rut = '654';
