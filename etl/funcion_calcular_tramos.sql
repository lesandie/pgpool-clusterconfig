-- Creamos una vista materializada para los conductores con su geometría y punto inicio y punto fin
DROP MATERIALIZED VIEW conductores;
CREATE MATERIALIZED VIEW conductores AS
(SELECT c.matricula, c.id_circuito, c.alumbrado, tc.tipo_conductor, tc.tense, c.the_geom, 
        ST_StartPoint(the_geom) AS punto_inicio, ST_EndPoint(the_geom) AS punto_fin
FROM vl_conductor_3857 AS c, cl_tipo_conductor AS tc
WHERE c.id_tipoconductor = tc.id_tipoconductor
GROUP BY c.matricula, c.id_circuito, c.alumbrado, tc.tipo_conductor, tc.tense, c.the_geom);
CREATE INDEX conductores_multi_idx ON conductores(matricula, id_circuito, alumbrado, tipo_conductor, tense);
-- Creamos una vista materializada para los tramos
DROP MATERIALIZED VIEW tramos;
CREATE MATERIALIZED VIEW tramos AS 
(SELECT c.matricula, c.id_circuito, c.alumbrado, tc.tipo_conductor, tc.tense, (ST_LineMerge(ST_Collect(array_agg(the_geom)))) AS geom_tramo 
FROM vl_conductor_3857 AS c, cl_tipo_conductor AS tc
WHERE c.id_tipoconductor = tc.id_tipoconductor
GROUP BY c.matricula, c.id_circuito, c.alumbrado, tc.tipo_conductor, tc.tense
ORDER BY c.matricula, c.id_circuito, c.alumbrado, tc.tipo_conductor, tc.tense);
-- vista materializada para apoyos
DROP MATERIALIZED VIEW apoyos;
CREATE MATERIALIZED VIEW apoyos AS 
(SELECT matricula,num_ap,the_geom FROM vl_apoyo_3857 
    GROUP BY matricula, num_ap,the_geom);
-- Creamos la tabla tramos
DROP TABLE vl_tramo_3857;
CREATE SEQUENCE vl_tramo_3857_id_tramo_seq;
CREATE TABLE vl_tramo_3857(
    id_tramo INTEGER NOT NULL DEFAULT nextval('vl_tramo_3857_id_tramo_seq'),
    matricula CHARACTER VARYING(30) NOT NULL,
    id_circuito INTEGER NOT NULL,
    alumbrado BOOLEAN,
    tipo_conductor CHARACTER VARYING(25),
    tense CHARACTER VARYING(25),
    the_geom geometry(LineString,3857),
    lista_apoyos TEXT,
    CONSTRAINT id_tramo_pkey PRIMARY KEY(id_tramo)
);
ALTER SEQUENCE vl_tramo_3857_id_tramo_seq OWNED BY vl_tramo_3857.id_tramo;
-- CREATE INDEX vl_tramo_3857_matricula_idx ON vl_tramo_3857(matricula, id_circuito, alumbrado, tipo_conductor, tense);    

-- Funcion que construye los tramos de una red y genera la lista ordenada de apoyos por tramo.
-- Como parámetro se le pasa la matrícula de la RED.
CREATE OR REPLACE FUNCTION funcion_calcular_tramos(TEXT) RETURNS VOID AS $$
DECLARE
    row_tramo RECORD;
    row_split_multi RECORD;
    row_apoyo RECORD;
    lista_orden_apoyos TEXT := NULL;
    id_tramo_anterior INTEGER:= NULL;
    num_apoyo INTEGER;
BEGIN
    -- Primero calcular tramos e insertarlos en la tabla de tramos
    -- REFRESH MATERIALIZED VIEW conductores WITH DATA;
    REFRESH MATERIALIZED VIEW tramos WITH DATA;
    REFRESH MATERIALIZED VIEW apoyos WITH DATA;
    DELETE FROM vl_tramo_3857 WHERE matricula = $1;
    FOR row_tramo IN SELECT * FROM tramos WHERE matricula = $1
        -- 1) Selecciono todos los conductores y genero tramos con ST_Collect y ST_linemerge
        -- Un tramo debe ser un linestring pero a veces se puede genera un multilinestring
    LOOP
        -- Dos casos de tramos: linestring (inserto directamente) y multilinestring (hago dump y reconstruyo varios tramos)
        CASE
            WHEN ST_GeometryType(row_tramo.geom_tramo) = 'ST_LineString' THEN
                INSERT INTO vl_tramo_3857 (matricula, id_circuito, alumbrado, tipo_conductor, tense, the_geom, lista_apoyos)
                VALUES (row_tramo.matricula, row_tramo.id_circuito, row_tramo.alumbrado,
                        row_tramo.tipo_conductor, row_tramo.tense, row_tramo.geom_tramo, 'X');
    
           WHEN ST_GeometryType(row_tramo.geom_tramo) = 'ST_MultiLineString' THEN
				FOR row_split_multi IN 
                    SELECT matricula, id_circuito, alumbrado, tipo_conductor, tense, 
                            (ST_Dump(geom_tramo)).geom FROM tramos																						   
                    WHERE matricula = row_tramo.matricula AND
                        id_circuito = row_tramo.id_circuito AND
                        alumbrado = row_tramo.alumbrado AND
                        tipo_conductor = row_tramo.tipo_conductor AND
                        tense = row_tramo.tense
                    GROUP BY matricula, id_circuito, alumbrado, tipo_conductor, tense, geom
                LOOP
                    --Descomentar para debug
                    --RAISE LOG '-----------------------------------';
					--RAISE LOG 'Matricula: %', row_split_multi.matricula;
					--RAISE LOG 'Circuito: %', row_split_multi.id_circuito;
					--RAISE LOG 'Alumbrado: %', row_split_multi.alumbrado;
					--RAISE LOG 'Tipo Conductor: %', row_split_multi.tipo_conductor;
					--RAISE LOG 'Tense: %', row_split_multi.tense;																		  
					--RAISE LOG 'Geometría tramo: %', ST_GeometryType(row_split_multi.geom);
                    INSERT INTO vl_tramo_3857 (matricula, id_circuito, alumbrado, tipo_conductor, tense, the_geom, lista_apoyos)
                    VALUES (row_split_multi.matricula, row_split_multi.id_circuito, row_split_multi.alumbrado,
                              row_split_multi.tipo_conductor, row_split_multi.tense, row_split_multi.geom, 'X');
                END LOOP;
        END CASE;
    END LOOP;
    --
    -- 2) Una vez generados los tramos, hay que calcular el orden de los apoyos
    FOR row_apoyo IN
    -- Selecciono cada uno de los tramos y la lista ordenada por geometria de puntos que lo componen con path y geom
        SELECT id_tramo, matricula, id_circuito, alumbrado, tipo_conductor, tense, (ST_DumpPoints(the_geom)).path[1], (ST_DumpPoints(the_geom)).geom
        FROM vl_tramo_3857 WHERE matricula = $1
        GROUP BY id_tramo, matricula, id_circuito, alumbrado, tipo_conductor, tense
    LOOP
        -- Busco el punto en la vista de apoyos y si son iguales y lo añado a la lista ordenada
        -- El campo matrícula es importante para reducir el escaneado en la tabla y el Limit 1 es para
        -- que sólo devuelva un punto. Un apoyo puede ser parte de varios tramos (y conductores)
        num_apoyo := (SELECT num_ap FROM apoyos 
                                WHERE matricula = row_apoyo.matricula 
                                AND ST_Equals(the_geom, row_apoyo.geom) LIMIT 1);
        -- Descomentar para debug
        --RAISE LOG '-----------------------------------';
	    --RAISE LOG 'Matricula: %', row_apoyo.matricula;
		--RAISE LOG 'Circuito: %', row_apoyo.id_circuito;
		--RAISE LOG 'Alumbrado: %', row_apoyo.alumbrado;
		--RAISE LOG 'Tipo Conductor: %', row_apoyo.tipo_conductor;
		--RAISE LOG 'Tense: %', row_apoyo.tense;
        --RAISE LOG 'id_Tramo: %', row_apoyo.id_tramo;
        --RAISE LOG 'Apoyo: %', num_apoyo;
        --
        -- Casos de primer tramo, tramo actual y nuevo tramo
        CASE 
            WHEN id_tramo_anterior IS NULL THEN 
                -- la comparacion tiene q ser IS, si fuese = la op daria NULL siempre
                lista_orden_apoyos := concat(num_apoyo::TEXT);
                -- concat() ignora los parametros null y los trata como vacio
                id_tramo_anterior := row_apoyo.id_tramo;
            WHEN (id_tramo_anterior = row_apoyo.id_tramo) AND (row_apoyo.path > 1) THEN   
                -- es el mismo tramo y vamos añadiendo puntos de apoyos intermedios a la lista
                -- cada 16 o 17 caracteres introduzco un ; para formatear la plantilla del plano
                IF (mod(char_length(lista_orden_apoyos),16) = 0 OR mod(char_length(lista_orden_apoyos),17) = 0) 
					AND char_length(lista_orden_apoyos) > 0
				THEN
                    lista_orden_apoyos := concat(lista_orden_apoyos, ';', num_apoyo::TEXT);
                ELSEIF lista_orden_apoyos = '' THEN
					lista_orden_apoyos := concat(num_apoyo::TEXT);
				ELSE
                    lista_orden_apoyos := concat(lista_orden_apoyos, ',', num_apoyo::TEXT);
                END IF;
            WHEN (id_tramo_anterior <> row_apoyo.id_tramo) AND (row_apoyo.path = 1) THEN
                -- Eliminar NULLs y comas varias ,,,, ; al principio y num_ap vacio
                IF position(',,' IN lista_orden_apoyos) > 0 
                OR position(',,,' IN lista_orden_apoyos) > 0
                OR right(lista_orden_apoyos, 1) = ','  
                OR lista_orden_apoyos = ';'
				OR lista_orden_apoyos =''
                THEN 
                    lista_orden_apoyos := 'X';
                END IF;
                UPDATE vl_tramo_3857 SET lista_apoyos = lista_orden_apoyos 
                                    WHERE id_tramo = id_tramo_anterior;
                lista_orden_apoyos := NULL;
                lista_orden_apoyos := concat(num_apoyo::TEXT);
                id_tramo_anterior := row_apoyo.id_tramo;   
        END CASE;    
    END LOOP;
END
$$ LANGUAGE plpgsql;
