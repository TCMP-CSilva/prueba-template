-- =========================================================
-- Archivo: test_full_rules_clean.sql
-- Objetivo: validar que el auditor no marque falsos positivos
-- =========================================================

------------------------------------------------------------
-- 1. SELECT correcto sin NOLOCK
------------------------------------------------------------
SELECT Id, Nombre
FROM dbo.Clientes;

------------------------------------------------------------
-- 2. Sin caracteres especiales prohibidos
------------------------------------------------------------
SELECT 'Correo: test[arroba]example[punto]com';
SELECT 'Precio: 10 pesos';

------------------------------------------------------------
-- 3. Sin temporales globales
------------------------------------------------------------
SELECT *
FROM #TmpValido;
-- nombre descriptivo, temporal local

------------------------------------------------------------
-- 4. Sin nombres genéricos
------------------------------------------------------------
DECLARE @tmp_regiones TABLE (Id INT,
    Nombre NVARCHAR(100));
SELECT *
FROM @tmp_regiones;

------------------------------------------------------------
-- 5. Sin uso de cursor
------------------------------------------------------------
DECLARE @i INT = 1;
WHILE @i <= 3
BEGIN
    PRINT @i;
    SET @i += 1;
END;

------------------------------------------------------------
-- 6. Sin funciones de usuario en WHERE
------------------------------------------------------------
SELECT *
FROM dbo.Empleados
WHERE Edad > 30;

------------------------------------------------------------
-- 7. JOIN con WHERE correcto
------------------------------------------------------------
SELECT a.Id, b.Nombre
FROM a
    INNER JOIN b ON a.Id = b.Id
WHERE b.Activo = 1;

------------------------------------------------------------
-- 8. SELECT sin *
------------------------------------------------------------
SELECT Id, Nombre
FROM dbo.Productos;

------------------------------------------------------------
-- 9. SELECT TOP correcto (paginación válida)
------------------------------------------------------------
SELECT TOP(10)
    Id, Nombre
FROM dbo.Clientes
ORDER BY Id;

------------------------------------------------------------
-- 10. UPDATE/DELETE con WHERE
------------------------------------------------------------
UPDATE dbo.Usuarios SET Estado = 'Activo' WHERE Id = 1;
DELETE FROM dbo.Clientes WHERE Id = 10;

------------------------------------------------------------
-- 11. INSERT con lista de columnas
------------------------------------------------------------
INSERT INTO dbo.Paises
    (Id, Nombre)
VALUES
    (1, 'Chile');
INSERT INTO dbo.Paises
    (Id, Nombre)
SELECT 2, 'Perú';

------------------------------------------------------------
-- 12. EXEC/sp_executesql parametrizado
------------------------------------------------------------
DECLARE @sql NVARCHAR(MAX), @id INT = 1;
SET @sql = N'SELECT * FROM dbo.Clientes WHERE Id=@id';
EXEC sp_executesql @sql, N'@id int', @id=@id;

------------------------------------------------------------
-- 13. SELECT DISTINCT justificado (warning silenciado)
------------------------------------------------------------
SELECT DISTINCT Nombre
FROM dbo.Empleados;
-- distinct-ok

------------------------------------------------------------
-- 14. Casos varios correctos
------------------------------------------------------------
-- Tablas temporales bien nombradas
CREATE TABLE #tmp_EmpleadosFiltrados
(
    Id INT,
    Nombre NVARCHAR(50)
);
INSERT INTO #tmp_EmpleadosFiltrados
    (Id, Nombre)
VALUES
    (1, 'Pedro');
SELECT Id, Nombre
FROM #tmp_EmpleadosFiltrados;

-- No hay SQL dinámico peligroso
EXEC sp_executesql N'SELECT Nombre FROM dbo.Regiones WHERE Id=@id',
                   N'@id int',
                   @id=1;

-- JOIN con WHERE, SELECT sin DISTINCT
SELECT a.Id, a.Nombre, b.Region
FROM a
    JOIN b ON a.RegionId = b.Id
WHERE b.Region = 'Norte';

-- Insert con columnas explícitas y commit controlado
BEGIN TRAN;
INSERT INTO dbo.Ventas
    (Id, Fecha, Monto)
VALUES
    (1, GETDATE(), 1000);
COMMIT;
