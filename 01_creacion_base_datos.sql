-- Reiniciar esquema si existe para permitir ejecuciones idempotentes
DROP TABLE IF EXISTS titulo_participacion CASCADE;
DROP TABLE IF EXISTS titulo_pais CASCADE;
DROP TABLE IF EXISTS titulo_genero CASCADE;
DROP TABLE IF EXISTS titulos CASCADE;
DROP TABLE IF EXISTS personas CASCADE;
DROP TABLE IF EXISTS generos CASCADE;
DROP TABLE IF EXISTS paises CASCADE;
DROP TABLE IF EXISTS clasificaciones CASCADE;
DROP TABLE IF EXISTS tipos_contenido CASCADE;

-- 1. TABLAS MAESTRAS (LÓGICA DE DOMINIO Y DICCIONARIOS)

-- Tabla Maestra: Tipos de Contenido (Movie / TV Show)
CREATE TABLE tipos_contenido (
    id_tipo_contenido SERIAL PRIMARY KEY,
    nombre_tipo VARCHAR(20) NOT NULL UNIQUE,
    CONSTRAINT chk_nombre_tipo CHECK (nombre_tipo IN ('Movie', 'TV Show'))
);
COMMENT ON TABLE tipos_contenido IS 'Tabla maestra de categorías primarias de contenido (Película o Serie)';
COMMENT ON COLUMN tipos_contenido.nombre_tipo IS 'Nombre del tipo de contenido: Movie o TV Show';
-- Tabla Maestra: Clasificaciones por Edad (Ratings)
CREATE TABLE clasificaciones (
    id_clasificacion SERIAL PRIMARY KEY,
    codigo_clasificacion VARCHAR(20) NOT NULL UNIQUE
);
COMMENT ON TABLE clasificaciones IS 'Tabla maestra con clasificaciones de público/edad (PG-13, TV-MA, R, etc.)';
-- Tabla Maestra: Países de Origen
CREATE TABLE paises (
    id_pais SERIAL PRIMARY KEY,
    nombre_pais VARCHAR(100) NOT NULL UNIQUE
);
COMMENT ON TABLE paises IS 'Tabla maestra de países de producción';
-- Tabla Maestra: Géneros y Categorías
CREATE TABLE generos (
    id_genero SERIAL PRIMARY KEY,
    nombre_genero VARCHAR(100) NOT NULL UNIQUE
);
COMMENT ON TABLE generos IS 'Tabla maestra de géneros cinematográficos y televisivos';
-- Tabla Maestra: Personas (Directores y Actores)
CREATE TABLE personas (
    id_persona SERIAL PRIMARY KEY,
    nombre_persona VARCHAR(255) NOT NULL UNIQUE
);
COMMENT ON TABLE personas IS 'Tabla maestra de participantes (directores, actores y elenco en general)';

-- 2. TABLA PRINCIPAL DE ENTIDAD (TÍTULOS NORMALIZADOS)

CREATE TABLE titulos (
    id_titulo SERIAL PRIMARY KEY,
    show_id_original VARCHAR(20) NOT NULL UNIQUE,
    titulo VARCHAR(255) NOT NULL,
    id_tipo_contenido INT NOT NULL REFERENCES tipos_contenido(id_tipo_contenido) ON DELETE RESTRICT,
    id_clasificacion INT REFERENCES clasificaciones(id_clasificacion) ON DELETE
    SET NULL,
        ano_lanzamiento SMALLINT CHECK (
            ano_lanzamiento >= 1800
            AND ano_lanzamiento <= 2100
        ),
        fecha_adicion DATE,
        duracion_valor INT CHECK (duracion_valor >= 0),
        duracion_unidad VARCHAR(20) CHECK (duracion_unidad IN ('min', 'Season', 'Seasons')),
        descripcion TEXT
);
COMMENT ON TABLE titulos IS 'Tabla principal conteniendo la información atómica de películas y series';
COMMENT ON COLUMN titulos.show_id_original IS 'Identificador original proveniente de la fuente desnormalizada (ej. s1, s2)';
COMMENT ON COLUMN titulos.duracion_valor IS 'Escalar numérico de la duración (minutos o cantidad de temporadas)';
COMMENT ON COLUMN titulos.duracion_unidad IS 'Unidad de medida de la duración: min, Season o Seasons';

-- 3. TABLAS ASOCIATIVAS (RELACIONES N:M)

-- Relación N:M entre Títulos y Géneros
CREATE TABLE titulo_genero (
    id_titulo INT NOT NULL REFERENCES titulos(id_titulo) ON DELETE CASCADE,
    id_genero INT NOT NULL REFERENCES generos(id_genero) ON DELETE CASCADE,
    CONSTRAINT pk_titulo_genero PRIMARY KEY (id_titulo, id_genero)
);
COMMENT ON TABLE titulo_genero IS 'Tabla de unión N:M entre Títulos y Géneros';
-- Relación N:M entre Títulos y Países
CREATE TABLE titulo_pais (
    id_titulo INT NOT NULL REFERENCES titulos(id_titulo) ON DELETE CASCADE,
    id_pais INT NOT NULL REFERENCES paises(id_pais) ON DELETE CASCADE,
    CONSTRAINT pk_titulo_pais PRIMARY KEY (id_titulo, id_pais)
);
COMMENT ON TABLE titulo_pais IS 'Tabla de unión N:M entre Títulos y Países de producción';
-- Relación N:M entre Títulos y Personas (con especificación de Rol)
CREATE TABLE titulo_participacion (
    id_titulo INT NOT NULL REFERENCES titulos(id_titulo) ON DELETE CASCADE,
    id_persona INT NOT NULL REFERENCES personas(id_persona) ON DELETE CASCADE,
    rol VARCHAR(20) NOT NULL,
    CONSTRAINT pk_titulo_participacion PRIMARY KEY (id_titulo, id_persona, rol),
    CONSTRAINT chk_rol_participacion CHECK (rol IN ('Director', 'Cast'))
);
COMMENT ON TABLE titulo_participacion IS 'Tabla de unión N:M entre Títulos y Personas con definición de rol (Director o Cast)';

-- 4. ÍNDICES DE OPTIMIZACIÓN

CREATE INDEX idx_titulos_tipo ON titulos(id_tipo_contenido);
CREATE INDEX idx_titulos_clasificacion ON titulos(id_clasificacion);
CREATE INDEX idx_titulos_ano ON titulos(ano_lanzamiento DESC);
CREATE INDEX idx_titulos_fecha_adicion ON titulos(fecha_adicion DESC);
CREATE INDEX idx_titulo_genero_genero ON titulo_genero(id_genero);
CREATE INDEX idx_titulo_pais_pais ON titulo_pais(id_pais);
CREATE INDEX idx_titulo_part_persona ON titulo_participacion(id_persona);
CREATE INDEX idx_titulo_part_rol ON titulo_participacion(rol);
