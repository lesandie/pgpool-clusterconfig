-- TRIGGER AFTER
CREATE OR REPLACE FUNCTION actualizar_vl_apoyo_conductor_tramo() RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
            PERFORM funcion_rotar_apoyos();
            PERFORM funcion_calcular_tramos(NEW.matricula);
    ELSEIF (TG_OP = 'DELETE') THEN
            PERFORM funcion_rotar_apoyos();
            PERFORM funcion_calcular_tramos(OLD.matricula);
    END IF;
    RETURN NULL;
END
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------
-- las estructuras NEW y OLD solo en triggers ROW-LEVEL
DROP TRIGGER vl_conductor_trigger ON vl_conductor_3857;
CREATE TRIGGER vl_conductor_trigger AFTER INSERT OR UPDATE OR DELETE 
ON vl_conductor_3857 FOR EACH ROW 
WHEN (pg_trigger_depth() = 0)
EXECUTE PROCEDURE actualizar_vl_apoyo_conductor_tramo();