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
CREATE TABLE ##global_temp_example
(
    id INT
);
GO

-- ===== PROBAR temp_names
DECLARE @temp TABLE (id INT);
CREATE TABLE #temp
(
    x INT
);
GO

-- ===== PROBAR cursors
DECLARE c CURSOR FOR SELECT Id
FROM dbo.Clientes;
OPEN c;
FETCH NEXT FROM c;
CLOSE c;
DEALLOCATE c;
GO

-- ===== PROBAR user_functions
SELECT id
FROM dbo.Clientes
WHERE dbo.fn_es_activo(id) = 1;
GO

-- ===== PROBAR scalar_udf_in_select_where
SELECT dbo.fn_calcula_descuento(monto) AS desc_calc
FROM dbo.Ordenes o
WHERE dbo.fn_valida_credito(o.clienteId) = 1;
GO

-- ===== PROBAR select_star
SELECT id
FROM dbo.Productos; -- Falta NOLOCK aquí también
GO

-- ===== PROBAR select_top + top_without_order_by
SELECT TOP 10
    p.Id, p.Nombre
FROM dbo.Productos p; -- sin ORDER BY
GO

-- ===== PROBAR nolock
SELECT p.Id, p.Nombre
FROM dbo.Productos p INNER JOIN dbo.Categorias c ON c.Id = p.CategoriaId;
GO

-- ===== PROBAR inner_join_where
SELECT p.Id, c.Nombre, m.Nombre
FROM dbo.Productos p
    INNER JOIN dbo.Categorias c ON c.Id = p.CategoriaId
    INNER JOIN dbo.Marcas m ON m.Id = p.MarcaId
WHERE p.Activo = 1;
GO

-- ===== PROBAR select_distinct_no_justification (SIN comentario)
SELECT DISTINCT p.CategoriaId
FROM dbo.Productos p;
GO

-- ===== PROBAR select_distinct_no_justification (CON justificación)
-- justification: Consolidamos resultados por categoría para reporte semestral
SELECT DISTINCT p.CategoriaId
FROM dbo.Productos p
WHERE p.Activo = 1;
GO

-- ===== PROBAR delete_update_without_where
DELETE FROM dbo.Ordenes;
UPDATE dbo.Clientes SET Activo = 0;
GO

-- ===== PROBAR delete_update_without_where2
DELETE FROM dbo.Ordenes;

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

-- ===== PROBAR hint_usage_general
SELECT p.Id
FROM dbo.Productos p WITH (INDEX(IX_Productos_Nombre))
    INNER LOOP JOIN dbo.Categorias c ON c.Id = p.CategoriaId
OPTION
(RECOMPILE);
GO
