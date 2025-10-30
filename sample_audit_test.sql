-- ===== PROBAR special_chars (caracteres especiales)
CREATE TABLE [ventas$]
(
    id INT,
    descripcion NVARCHAR(100)
);
GO

-- ===== PROBAR deprecated_types (TEXT/NTEXT/IMAGE)
CREATE TABLE dbo.DeprecatedDemo
(
    oldText TEXT,
    oldImage IMAGE,
    oldNtext NTEXT
);
GO

-- ===== PROBAR global_temp (##)
CREATE TABLE ##global_temp_example
(
    id INT
);
GO

-- ===== PROBAR temp_names (nombres genéricos)
DECLARE @temp TABLE (id INT);
CREATE TABLE #temp
(
    x INT
);
GO

-- ===== PROBAR cursors
DECLARE c CURSOR FOR SELECT *
FROM dbo.Clientes;
OPEN c;
FETCH NEXT FROM c;
CLOSE c;
DEALLOCATE c;
GO

-- ===== PROBAR user_functions (en WHERE)
SELECT id
FROM dbo.Clientes
WHERE dbo.fn_es_activo(id) = 1;
GO

-- ===== PROBAR scalar_udf_in_select_where (SELECT y WHERE)
SELECT dbo.fn_calcula_descuento(monto) AS desc_calc
FROM dbo.Ordenes o
WHERE dbo.fn_valida_credito(o.clienteId) = 1;
GO

-- ===== PROBAR select_star
SELECT *
FROM dbo.Productos; -- falta NOLOCK aquí también
GO

-- ===== PROBAR select_top + top_without_order_by
SELECT TOP 10
    p.Id, p.Nombre
FROM dbo.Productos p; -- sin ORDER BY
GO

-- ===== PROBAR nolock (debe exigir WITH (NOLOCK); saltará sys.* y #/@)
SELECT p.Id, p.Nombre
FROM dbo.Productos p INNER JOIN dbo.Categorias c ON c.Id = p.CategoriaId;
GO

-- ===== PROBAR inner_join_where (múltiples INNER JOIN + WHERE sin variantes)
SELECT p.Id, c.Nombre, m.Nombre
FROM dbo.Productos p
    INNER JOIN dbo.Categorias c ON c.Id = p.CategoriaId
    INNER JOIN dbo.Marcas m ON m.Id = p.MarcaId
WHERE p.Activo = 1;
GO

-- ===== PROBAR select_distinct_no_justification (SIN comentario de justificación)
SELECT DISTINCT p.CategoriaId
FROM dbo.Productos p;
GO

-- ===== PROBAR select_distinct_no_justification (CON justificación - NO debe caer)
-- justification: Consolidamos resultados por categoría para reporte semestral
SELECT DISTINCT p.CategoriaId
FROM dbo.Productos p
WHERE p.Activo = 1;
GO

-- ===== PROBAR delete_update_without_where
DELETE FROM dbo.Ordenes;
UPDATE dbo.Clientes SET Activo = 0;
GO

-- ===== PROBAR exec_dynamic_sql_unparameterized
DECLARE @col NVARCHAR(50) = 'Nombre';
DECLARE @sql NVARCHAR(MAX) = 'SELECT ' + @col + ' FROM dbo.Productos';
-- concatenación
EXEC(@sql);
EXEC sp_executesql @sql; -- concatenación previa
GO

-- ===== PROBAR select_into_heavy
SELECT p.Id, p.Nombre
INTO #tmpProductos
FROM dbo.Productos p;
GO

-- ===== PROBAR hint_usage_general (WITH INDEX, OPTION(RECOMPILE), JOIN hints)
SELECT p.Id
FROM dbo.Productos p WITH (INDEX(IX_Productos_Nombre))
    INNER LOOP JOIN dbo.Categorias c ON c.Id = p.CategoriaId
OPTION
(RECOMPILE);
GO
