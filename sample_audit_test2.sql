-- ===== PROBAR special_chars
CREATE TABLE [ventas$]
(
    id INT,
    descripcion NVARCHAR(100)
);
GO

-- ===== PROBAR deprecated_types
CREATE TABLE dbo.DeprecatedDemo
(
    oldText TEXT,
    oldImage IMAGE,
    oldNtext NTEXT
);
GO

-- ===== PROBAR global_temp

-- ===== PROBAR temp_names
DECLARE @temp1 TABLE (id INT);
CREATE TABLE #temp1
(
    x INT
);
GO

-- ===== PROBAR cursors


-- ===== PROBAR user_functions
SELECT id
FROM dbo.Clientes WITH (NOLOCK)
WHERE dbo.fn_es_activo(id) = 1;
GO

-- ===== PROBAR scalar_udf_in_select_where
SELECT dbo.fn_calcula_descuento(monto) AS desc_calc
FROM dbo.Ordenes o (NOLOCK)
WHERE dbo.fn_valida_credito(o.clienteId) = 1;
GO

-- ===== PROBAR select_star
SELECT id
FROM dbo.Productos WITH (NOLOCK); -- Falta NOLOCK aquí también
GO

-- ===== PROBAR select_top + top_without_order_by
SELECT TOP 10
    p.Id, p.Nombre
FROM dbo.Productos p WITH (NOLOCK); -- sin ORDER BY
GO

-- ===== PROBAR nolock
SELECT p.Id, p.Nombre
FROM dbo.Productos p WITH (NOLOCK) INNER JOIN dbo.Categorias c WITH (NOLOCK) ON c.Id = p.CategoriaId;
GO

-- ===== PROBAR inner_join_where
SELECT p.Id, c.Nombre, m.Nombre
FROM dbo.Productos p WITH (NOLOCK)
    INNER JOIN dbo.Categorias c WITH (NOLOCK) ON c.Id = p.CategoriaId
    INNER JOIN dbo.Marcas m WITH (NOLOCK) ON m.Id = p.MarcaId
WHERE p.Activo = 1;
GO

-- ===== PROBAR select_distinct_no_justification (SIN comentario)
-- justification: consolidamos categorías únicas para reporte mensual
SELECT DISTINCT p.CategoriaId
FROM dbo.Productos p WITH (NOLOCK);
GO

-- ===== PROBAR select_distinct_no_justification (CON justificación)
-- justification: Consolidamos resultados por categoría para reporte semestral
SELECT DISTINCT p.CategoriaId
FROM dbo.Productos p WITH (NOLOCK)
WHERE p.Activo = 1;
GO

-- ===== PROBAR delete_update_without_where
DELETE FROM dbo.Ordenes WHERE p.Activo = 1;
UPDATE dbo.Clientes SET Activo = 0;
GO

-- ===== PROBAR delete_update_without_where2
DELETE FROM dbo.Ordene WHERE p.Activo = 1;

-- ===== PROBAR exec_dynamic_sql_unparameterized
DECLARE @col NVARCHAR(50) = 'Nombre';
DECLARE @sql NVARCHAR(MAX) = 'SELECT ' + @col + ' FROM dbo.Productos WITH (NOLOCK)';
-- concatenación
EXEC(@sql);
EXEC sp_executesql @sql; -- concatenación previa
GO

-- ===== PROBAR select_into_heavy
SELECT p.Id, p.Nombre
INTO #tmpProductos
FROM dbo.Productos p WITH (NOLOCK);
GO
