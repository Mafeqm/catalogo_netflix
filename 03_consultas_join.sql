
-- FASE VI: EXPLOTACIÓN ANALÍTICA MEDIANTE CONSULTAS SQL (JOIN)

-- Catálogo Cinematográfico por Género
-- Filtra películas de un género específico, ordenadas de la más reciente a la más antigua.
SELECT 
    t.titulo,
    t.ano_lanzamiento,
    c.codigo_clasificacion AS clasificacion,
    t.duracion_valor || ' ' || t.duracion_unidad AS duracion,
    g.nombre_genero AS genero
FROM titulos t
JOIN tipos_contenido tc ON t.id_tipo_contenido = tc.id_tipo_contenido
LEFT JOIN clasificaciones c ON t.id_clasificacion = c.id_clasificacion
JOIN titulo_genero tg ON t.id_titulo = tg.id_titulo
JOIN generos g ON tg.id_genero = g.id_genero
WHERE tc.nombre_tipo = 'Movie' 
  AND g.nombre_genero = 'Dramas' -- Parámetro de filtrado (puedes cambiar 'Dramas' por 'Comedies', etc.)
ORDER BY t.ano_lanzamiento DESC;


-- Consulta B: Trazabilidad Geográfica y de Participación
-- Muestra los participantes y sus roles en producciones de un país específico.
SELECT 
    t.titulo,
    tc.nombre_tipo AS tipo_produccion,
    pa.nombre_pais AS pais_origen,
    pe.nombre_persona AS participante,
    tp.rol,
    t.ano_lanzamiento AS ano_estreno
FROM titulos t
JOIN tipos_contenido tc ON t.id_tipo_contenido = tc.id_tipo_contenido
JOIN titulo_pais tpa ON t.id_titulo = tpa.id_titulo
JOIN paises pa ON tpa.id_pais = pa.id_pais
JOIN titulo_participacion tp ON t.id_titulo = tp.id_titulo
JOIN personas pe ON tp.id_persona = pe.id_persona
WHERE pa.nombre_pais = 'Colombia' -- Parámetro de filtrado (puedes cambiarlo por 'Mexico', 'United States', etc.)
ORDER BY t.titulo ASC, tp.rol ASC;