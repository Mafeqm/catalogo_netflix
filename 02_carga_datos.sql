-- 1. CREACIÓN DE TABLA DE TRÁNSITO (STAGING)
DROP TABLE IF EXISTS netflix_staging;

CREATE UNLOGGED TABLE netflix_staging (
    show_id VARCHAR(20),
    type VARCHAR(50),
    title VARCHAR(255),
    director TEXT,
    cast_list TEXT,
    country TEXT,
    date_added VARCHAR(100),
    release_year INT,
    rating VARCHAR(50),
    duration VARCHAR(50),
    listed_in TEXT,
    description TEXT
);

COMMENT ON TABLE netflix_staging IS 'Tabla temporal de tránsito desnormalizada para la recepción del CSV crudo';


-- 2. CARGA MASIVA DESDE CSV

x
COPY netflix_staging(show_id, type, title, director, cast_list, country, date_added, release_year, rating, duration, listed_in, description)
FROM 'data/netflix_titles.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');


-- 3. SANITIZACIÓN Y LIMPIEZA DE DATOS EN STAGING

-- 3.1 Manejo de desalineación conocida en dataset (duraciones en la columna rating)
UPDATE netflix_staging
SET 
    duration = rating,
    rating = NULL
WHERE rating LIKE '%min%' OR rating LIKE '%Season%';

-- 3.2 Limpieza de espacios en blanco y conversión de cadenas vacías a NULL
UPDATE netflix_staging
SET 
    show_id     = NULLIF(TRIM(show_id), ''),
    type        = NULLIF(TRIM(type), ''),
    title       = NULLIF(TRIM(title), ''),
    director    = NULLIF(TRIM(director), ''),
    cast_list   = NULLIF(TRIM(cast_list), ''),
    country     = NULLIF(TRIM(country), ''),
    date_added  = NULLIF(TRIM(date_added), ''),
    rating      = NULLIF(TRIM(rating), ''),
    duration    = NULLIF(TRIM(duration), ''),
    listed_in   = NULLIF(TRIM(listed_in), ''),
    description = NULLIF(TRIM(description), '');


-- 4. POBLAMIENTO DE TABLAS MAESTRAS (DICCIONARIOS 3NF)


-- 4.1 Tipos de Contenido
INSERT INTO tipos_contenido (nombre_tipo)
SELECT DISTINCT type
FROM netflix_staging
WHERE type IS NOT NULL
ON CONFLICT (nombre_tipo) DO NOTHING;

-- 4.2 Clasificaciones por Edad
INSERT INTO clasificaciones (codigo_clasificacion)
SELECT DISTINCT rating
FROM netflix_staging
WHERE rating IS NOT NULL
ON CONFLICT (codigo_clasificacion) DO NOTHING;

-- 4.3 Países (Desglosado de listas multivaluadas con string_to_array + unnest)
INSERT INTO paises (nombre_pais)
SELECT DISTINCT TRIM(item_pais)
FROM netflix_staging s,
     UNNEST(string_to_array(s.country, ',')) AS item_pais
WHERE s.country IS NOT NULL AND TRIM(item_pais) <> ''
ON CONFLICT (nombre_pais) DO NOTHING;

-- 4.4 Géneros (Desglosado de listas multivaluadas con string_to_array + unnest)
INSERT INTO generos (nombre_genero)
SELECT DISTINCT TRIM(item_genero)
FROM netflix_staging s,
     UNNEST(string_to_array(s.listed_in, ',')) AS item_genero
WHERE s.listed_in IS NOT NULL AND TRIM(item_genero) <> ''
ON CONFLICT (nombre_genero) DO NOTHING;

-- 4.5 Personas (Directores y Actores combinados sin duplicados)
INSERT INTO personas (nombre_persona)
SELECT DISTINCT TRIM(item_persona)
FROM (
    SELECT UNNEST(string_to_array(director, ',')) AS item_persona 
    FROM netflix_staging 
    WHERE director IS NOT NULL
    UNION
    SELECT UNNEST(string_to_array(cast_list, ',')) AS item_persona 
    FROM netflix_staging 
    WHERE cast_list IS NOT NULL
) AS subquery_personas
WHERE TRIM(item_persona) <> ''
ON CONFLICT (nombre_persona) DO NOTHING;


-- 5. POBLAMIENTO DE LA TABLA PRINCIPAL (TITULOS)


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
    s.show_id,
    s.title,
    tc.id_tipo_contenido,
    c.id_clasificacion,
    s.release_year,
    -- Conversión a tipo DATE (esperado: Month DD, YYYY)
    CASE 
        WHEN s.date_added IS NOT NULL THEN TO_DATE(s.date_added, 'FMMonth DD, YYYY')
        ELSE NULL
    END AS fecha_adicion,
    -- Extracción escalar de la duración (ej. '90 min' -> 90)
    CASE 
        WHEN s.duration IS NOT NULL AND s.duration ~ '^[0-9]+' 
        THEN CAST(SPLIT_PART(s.duration, ' ', 1) AS INT)
        ELSE NULL
    END AS duracion_valor,
    -- Extracción de la unidad de duración (ej. '90 min' -> 'min')
    CASE 
        WHEN s.duration IS NOT NULL AND s.duration ~ '^[0-9]+' 
        THEN SPLIT_PART(s.duration, ' ', 2)
        ELSE NULL
    END AS duracion_unidad,
    s.description
FROM netflix_staging s
JOIN tipos_contenido tc ON tc.nombre_tipo = s.type
LEFT JOIN clasificaciones c ON c.codigo_clasificacion = s.rating
ON CONFLICT (show_id_original) DO NOTHING;


-- 6. POBLAMIENTO DE TABLAS ASOCIATIVAS (RELACIONES N:M)


-- 6.1 Relación Título <-> Género
INSERT INTO titulo_genero (id_titulo, id_genero)
SELECT DISTINCT
    t.id_titulo,
    g.id_genero
FROM netflix_staging s
JOIN titulos t ON t.show_id_original = s.show_id
CROSS JOIN LATERAL UNNEST(string_to_array(s.listed_in, ',')) AS item_genero
JOIN generos g ON g.nombre_genero = TRIM(item_genero)
WHERE s.listed_in IS NOT NULL
ON CONFLICT (id_titulo, id_genero) DO NOTHING;

-- 6.2 Relación Título <-> País
INSERT INTO titulo_pais (id_titulo, id_pais)
SELECT DISTINCT
    t.id_titulo,
    p.id_pais
FROM netflix_staging s
JOIN titulos t ON t.show_id_original = s.show_id
CROSS JOIN LATERAL UNNEST(string_to_array(s.country, ',')) AS item_pais
JOIN paises p ON p.nombre_pais = TRIM(item_pais)
WHERE s.country IS NOT NULL
ON CONFLICT (id_titulo, id_pais) DO NOTHING;

-- 6.3 Relación Título <-> Persona (Directores)
INSERT INTO titulo_participacion (id_titulo, id_persona, rol)
SELECT DISTINCT
    t.id_titulo,
    p.id_persona,
    'Director' AS rol
FROM netflix_staging s
JOIN titulos t ON t.show_id_original = s.show_id
CROSS JOIN LATERAL UNNEST(string_to_array(s.director, ',')) AS item_director
JOIN personas p ON p.nombre_persona = TRIM(item_director)
WHERE s.director IS NOT NULL
ON CONFLICT (id_titulo, id_persona, rol) DO NOTHING;

-- 6.4 Relación Título <-> Persona (Elenco / Cast)
INSERT INTO titulo_participacion (id_titulo, id_persona, rol)
SELECT DISTINCT
    t.id_titulo,
    p.id_persona,
    'Cast' AS rol
FROM netflix_staging s
JOIN titulos t ON t.show_id_original = s.show_id
CROSS JOIN LATERAL UNNEST(string_to_array(s.cast_list, ',')) AS item_cast
JOIN personas p ON p.nombre_persona = TRIM(item_cast)
WHERE s.cast_list IS NOT NULL
ON CONFLICT (id_titulo, id_persona, rol) DO NOTHING;


-- 7. ELIMINACIÓN DE TABLA DE TRÁNSITO TRAS FINALIZAR ETL


DROP TABLE IF EXISTS netflix_staging;

