# Guía Técnica: Documento Dump y Restauración de Base de Datos PostgreSQL

## 1. Introducción al Documento Dump (SQL Dump)

Un **Dump de Base de Datos** (SQL Dump) es un archivo de respaldo que contiene la representación en código SQL completo de la estructura (DDL - *Data Definition Language*) y de los datos (DML - *Data Manipulation Language*) de una base de datos relacional. 

A diferencia de un archivo desnormalizado (como un CSV), el documento dump generado (`04_dump_base_datos.sql` / `dump.sql`) es totalmente **autónomo e idempotente**: permite recrear y restaurar la base de datos en estado **Tercera Forma Normal (3NF)** con todas sus relaciones, claves primarias, claves foráneas, restricciones de integridad e índices de optimización sin depender de herramientas externas o procesos ETL previos.

---

## 2. Estructura del Archivo `04_dump_base_datos.sql`

El archivo dump generado sigue la especificación técnica de exportación estándar de PostgreSQL (`pg_dump`) estructurado en las siguientes fases:

1. **Configuración de Sesión y Encabezado:**
   - Establece codificación `UTF8`, comportamientos de cadenas estándar y suprime mensajes innecesarios de advertencia.
2. **Reinicio Idempotente de Esquema (DDL Cleanup):**
   - Ejecuta sentencias `DROP TABLE IF EXISTS ... CASCADE` en orden inverso a las dependencias relacionales para limpiar previa existencia de tablas.
3. **Creación de Estructura 3NF (DDL Schema):**
   - **5 Tablas Maestras:** `tipos_contenido`, `clasificaciones`, `paises`, `generos`, `personas`.
   - **1 Tabla de Entidad Principal:** `titulos` (con claves foráneas hacia `tipos_contenido` y `clasificaciones`).
   - **3 Tablas Asociativas N:M:** `titulo_genero`, `titulo_pais`, `titulo_participacion` (con roles `Director` y `Cast`).
4. **Inserción de Datos Normalizados (DML Data):**
   - Sentencias `INSERT INTO` explícitas ordenadas por precedencia de claves foráneas con 8,807 títulos de Netflix totalmente atómicos y atados a sus maestros relacionales.
5. **Ajuste de Secuencias Autoincrementales:**
   - Sentencias `SELECT pg_catalog.setval(...)` para sincronizar los contadores `SERIAL` con los IDs insertados.
6. **Índices de Optimización de Consultas:**
   - Creación de índices `B-Tree` sobre claves foráneas, fechas y columnas de filtrado frecuente (`id_tipo_contenido`, `id_clasificacion`, `ano_lanzamiento DESC`, `fecha_adicion DESC`, `id_genero`, `id_pais`, `id_persona`, `rol`).

---

## 3. Comandos CLI para Generar Dumps en PostgreSQL (`pg_dump`)

Para generar manualmente un dump desde la línea de comandos de PostgreSQL en un entorno de producción o desarrollo:

### A. Formato Texto Plano (`.sql`)
Genera un script SQL ejecutable desde cualquier cliente (psql, pgAdmin, DBeaver):
```bash
pg_dump -U postgres -h localhost -port 5432 -d catalogo_netflix --clean --if-exists --no-owner --no-privileges --column-inserts -f 04_dump_base_datos.sql
```

**Parámetros clave:**
- `-U postgres`: Usuario de PostgreSQL.
- `-d catalogo_netflix`: Nombre de la base de datos origen.
- `--clean --if-exists`: Incluye los comandos `DROP TABLE IF EXISTS` para reinicios limpios.
- `--no-owner`: Omite asignaciones de usuario propietario (mejora la portabilidad entre diferentes servidores).
- `--column-inserts`: Genera sentencias `INSERT INTO tabla (col1, col2) VALUES (...)` en lugar de bloques `COPY`.

### B. Formato Binario / Custom (`.dump` / `.tar`)
Genera un archivo comprimido optimizado para bases de datos de gran volumen:
```bash
pg_dump -U postgres -h localhost -d catalogo_netflix -F c -b -v -f catalogo_netflix.dump
```
- `-F c`: Formato personalizado (*Custom format*) nativo de PostgreSQL.

---

## 4. Guía de Restauración de la Base de Datos

### Opción 1: Restaurar desde el Documento `04_dump_base_datos.sql` usando `psql`

1. **Crear la base de datos destino (si no existe):**
   ```bash
   createdb -U postgres -h localhost catalogo_netflix
   ```

2. **Ejecutar el archivo Dump en la base de datos:**
   ```bash
   psql -U postgres -h localhost -d catalogo_netflix -f 04_dump_base_datos.sql
   ```

3. **Restaurar directamente desde cliente gráfico (pgAdmin / DBeaver / VS Code SQL):**
   - Abrir una nueva conexión a la base de datos `catalogo_netflix`.
   - Abrir el archivo `04_dump_base_datos.sql`.
   - Ejecutar la totalidad del script (*Execute Script / F5*).

### Opción 2: Restaurar desde respaldo binario usando `pg_restore`

Si se utiliza un archivo en formato binario (`.dump`):
```bash
pg_restore -U postgres -h localhost -d catalogo_netflix -c -v catalogo_netflix.dump
```

---

## 5. Verificación e Integridad Post-Restauración

Tras ejecutar la restauración mediante el dump, puede validarse la cantidad de registros e integridad relacional ejecutando la siguiente consulta en SQL:

```sql
SELECT 'tipos_contenido' AS tabla, COUNT(*) AS total FROM tipos_contenido
UNION ALL SELECT 'clasificaciones', COUNT(*) FROM clasificaciones
UNION ALL SELECT 'paises', COUNT(*) FROM paises
UNION ALL SELECT 'generos', COUNT(*) FROM generos
UNION ALL SELECT 'personas', COUNT(*) FROM personas
UNION ALL SELECT 'titulos', COUNT(*) FROM titulos
UNION ALL SELECT 'titulo_genero', COUNT(*) FROM titulo_genero
UNION ALL SELECT 'titulo_pais', COUNT(*) FROM titulo_pais
UNION ALL SELECT 'titulo_participacion', COUNT(*) FROM titulo_participacion;
```

**Resultados esperados post-restauración:**
- `tipos_contenido`: 2 registros (Movie, TV Show)
- `clasificaciones`: 14 registros
- `paises`: 127 registros
- `generos`: 42 registros
- `personas`: 39,289 registros
- `titulos`: 8,807 registros
- `titulo_genero`: 19,323 relaciones
- `titulo_pais`: 10,012 relaciones
- `titulo_participacion`: 71,101 relaciones (directores y cast)
