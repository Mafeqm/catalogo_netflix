-- =============================================================================
-- FASE V: PROCESO ETL Y CARGA DE DATOS NORMALIZADA (3NF)
-- Dataset: netflix_titles.csv
-- =============================================================================

-- 1. TABLA TEMPORAL / STAGING
-- Estructura desnormalizada idéntica a las columnas del CSV original.
DROP TABLE IF EXISTS netflix_staging CASCADE;

CREATE TABLE netflix_staging (
    show_id VARCHAR(50),
    type VARCHAR(50),
    title VARCHAR(255),
    director TEXT,
    "cast" TEXT,
    country TEXT,
    date_added VARCHAR(100),
    release_year INT,
    rating VARCHAR(50),
    duration VARCHAR(50),
    listed_in TEXT,
    description TEXT
);

-- Carga masiva de datos desnormalizados desde el archivo CSV
-- NOTA: Ejecutar este comando en psql o cliente SQL compatible con \copy
\copy netflix_staging FROM 'netflix_titles.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- 2. POBLAR TABLAS MAESTRAS (DICCIONARIOS 3NF)

-- A. Tipos de Contenido (Movie, TV Show)
INSERT INTO tipos_contenido (nombre_tipo)
SELECT DISTINCT TRIM(type)
FROM netflix_staging
WHERE type IS NOT NULL AND TRIM(type) != ''
ON CONFLICT (nombre_tipo) DO NOTHING;

-- B. Clasificaciones por Edad (Ratings)
-- Filtramos posibles anomalías en la columna rating (ej. valores de duración en rating)
INSERT INTO clasificaciones (codigo_clasificacion)
SELECT DISTINCT TRIM(rating)
FROM netflix_staging
WHERE rating IS NOT NULL 
  AND TRIM(rating) != ''
  AND TRIM(rating) NOT LIKE '%min%' 
  AND TRIM(rating) NOT LIKE '%Season%'
ON CONFLICT (codigo_clasificacion) DO NOTHING;

-- C. Países de Producción
-- Descomposición de listas separadas por comas utilizando string_to_array + unnest
INSERT INTO paises (nombre_pais)
SELECT DISTINCT TRIM(unnest(string_to_array(country, ','))) AS pais
FROM netflix_staging
WHERE country IS NOT NULL AND TRIM(country) != ''
ON CONFLICT (nombre_pais) DO NOTHING;

-- D. Géneros / Categorías
INSERT INTO generos (nombre_genero)
SELECT DISTINCT TRIM(unnest(string_to_array(listed_in, ','))) AS genero
FROM netflix_staging
WHERE listed_in IS NOT NULL AND TRIM(listed_in) != ''
ON CONFLICT (nombre_genero) DO NOTHING;

-- E. Personas (Directores y Actores)
-- Consolidación de nombres únicos de directores y reparto
INSERT INTO personas (nombre_persona)
SELECT DISTINCT persona
FROM (
    SELECT TRIM(unnest(string_to_array(director, ','))) AS persona
    FROM netflix_staging
    WHERE director IS NOT NULL AND TRIM(director) != ''
    UNION
    SELECT TRIM(unnest(string_to_array("cast", ','))) AS persona
    FROM netflix_staging
    WHERE "cast" IS NOT NULL AND TRIM("cast") != ''
) p
WHERE persona IS NOT NULL AND persona != ''
ON CONFLICT (nombre_persona) DO NOTHING;


-- 3. POBLAR TABLA PRINCIPAL ENTIDAD (TITULOS)

INSERT INTO titulos (
    show_id_original,
    titulo,
    id_tipo_contenido,
    id_clasificacion,
    ano_lanzamiento,
    fecha_adicion,
    duracion_valor,
    duracion_unidad,
    descripcion
)
SELECT 
    TRIM(s.show_id) AS show_id_original,
    TRIM(s.title) AS titulo,
    tc.id_tipo_contenido,
    c.id_clasificacion,
    s.release_year AS ano_lanzamiento,
    CASE 
        WHEN s.date_added IS NOT NULL AND TRIM(s.date_added) != '' THEN
            TO_DATE(TRIM(s.date_added), 'Month DD, YYYY')
        ELSE NULL
    END AS fecha_adicion,
    CASE 
        WHEN s.duration IS NOT NULL AND TRIM(s.duration) ~ '^[0-9]+' THEN
            CAST(SPLIT_PART(TRIM(s.duration), ' ', 1) AS INT)
        ELSE NULL
    END AS duracion_valor,
    CASE 
        WHEN s.duration IS NOT NULL AND TRIM(s.duration) ~ '^[0-9]+' THEN
            SPLIT_PART(TRIM(s.duration), ' ', 2)
        ELSE NULL
    END AS duracion_unidad,
    TRIM(s.description) AS descripcion
FROM netflix_staging s
JOIN tipos_contenido tc ON tc.nombre_tipo = TRIM(s.type)
LEFT JOIN clasificaciones c ON c.codigo_clasificacion = TRIM(s.rating)
ON CONFLICT (show_id_original) DO NOTHING;


-- 4. POBLAR TABLAS ASOCIATIVAS (RELACIONES N:M)

-- A. Relación Títulos - Géneros
INSERT INTO titulo_genero (id_titulo, id_genero)
SELECT DISTINCT 
    t.id_titulo,
    g.id_genero
FROM netflix_staging s
JOIN titulos t ON t.show_id_original = TRIM(s.show_id)
CROSS JOIN LATERAL unnest(string_to_array(s.listed_in, ',')) AS item_genero
JOIN generos g ON g.nombre_genero = TRIM(item_genero)
ON CONFLICT (id_titulo, id_genero) DO NOTHING;

-- B. Relación Títulos - Países
INSERT INTO titulo_pais (id_titulo, id_pais)
SELECT DISTINCT 
    t.id_titulo,
    p.id_pais
FROM netflix_staging s
JOIN titulos t ON t.show_id_original = TRIM(s.show_id)
CROSS JOIN LATERAL unnest(string_to_array(s.country, ',')) AS item_pais
JOIN paises p ON p.nombre_pais = TRIM(item_pais)
ON CONFLICT (id_titulo, id_pais) DO NOTHING;

-- C. Relación Títulos - Personas (Directores)
INSERT INTO titulo_participacion (id_titulo, id_persona, rol)
SELECT DISTINCT 
    t.id_titulo,
    per.id_persona,
    'Director' AS rol
FROM netflix_staging s
JOIN titulos t ON t.show_id_original = TRIM(s.show_id)
CROSS JOIN LATERAL unnest(string_to_array(s.director, ',')) AS item_director
JOIN personas per ON per.nombre_persona = TRIM(item_director)
ON CONFLICT (id_titulo, id_persona, rol) DO NOTHING;

-- D. Relación Títulos - Personas (Cast / Actores)
INSERT INTO titulo_participacion (id_titulo, id_persona, rol)
SELECT DISTINCT 
    t.id_titulo,
    per.id_persona,
    'Cast' AS rol
FROM netflix_staging s
JOIN titulos t ON t.show_id_original = TRIM(s.show_id)
CROSS JOIN LATERAL unnest(string_to_array(s."cast", ',')) AS item_cast
JOIN personas per ON per.nombre_persona = TRIM(item_cast)
ON CONFLICT (id_titulo, id_persona, rol) DO NOTHING;


-- 5. VERIFICACIÓN Y LIMPIEZA POST-ETL
DROP TABLE IF EXISTS netflix_staging CASCADE;

-- Consultas de resumen de carga
SELECT 'tipos_contenido' AS tabla, COUNT(*) AS total_registros FROM tipos_contenido
UNION ALL
SELECT 'clasificaciones', COUNT(*) FROM clasificaciones
UNION ALL
SELECT 'paises', COUNT(*) FROM paises
UNION ALL
SELECT 'generos', COUNT(*) FROM generos
UNION ALL
SELECT 'personas', COUNT(*) FROM personas
UNION ALL
SELECT 'titulos', COUNT(*) FROM titulos
UNION ALL
SELECT 'titulo_genero', COUNT(*) FROM titulo_genero
UNION ALL
SELECT 'titulo_pais', COUNT(*) FROM titulo_pais
UNION ALL
SELECT 'titulo_participacion', COUNT(*) FROM titulo_participacion;
