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
-- 

DECLARE
		@Report_Name 	 VARCHAR(256),
		@Reprocess_Date  DATE,
		@Exec_Date 	     DATE,
		@FileName     	 VARCHAR(256),
		@Format       	 VARCHAR(256),
		@Extension    	 VARCHAR(256),
		@PathOutput   	 VARCHAR(256),
		@ParamList       NVARCHAR(MAX),
		@LinuxCmd 		 VARCHAR(MAX);

-- Obtener Report_Name y Reprocess_Date
SELECT
    @Report_Name = Report_Name,
    @Reprocess_Date = Reprocess_Date
FROM Kustom.dbo.TBL_REG_AUTO_REPORT WITH(NOLOCK)
WHERE 
		Report_Id = @Report_Id;

-- Calcular fecha de ejecucion
SET @Exec_Date = 
		CASE 
			WHEN @Reprocess_Date = '1900-01-01' THEN GETDATE()
			ELSE @Reprocess_Date
		END;

--Armar lista de parametros del Open Report
;WITH
    Paramcontrol
    AS
    
    (

        SELECT Param_Value,
            Param_Order
				, ROW_NUMBER() OVER(PARTITION BY Param_Order ORDER BY Exec_Profile) AS RN
        FROM Kustom..TBL_REG_AUTO_REPORT_PARAMETER WITH(NOLOCK)
        WHERE Report_Id = @Report_Id
            AND Exec_Id = @Exec_Id
            AND Param_Order IS NOT NULL

    )
SELECT @ParamList = 
				STUFF((
						SELECT '  ' + Param_Value
    FROM Paramcontrol
    WHERE RN = 1
    ORDER BY Param_Order ASC
    FOR XML PATH(''), TYPE
				).value('.', 'NVARCHAR(MAX)'), 1, 2, '');

-- Limpiar espacios duplicados
SET @ParamList = REPLACE(@ParamList, '  ', ' ');

-- Obtener parametros del comando
SELECT
    @FileName   = MAX(CASE WHEN Param_Name = 'FileName'  THEN Param_Value END),
    @Format     = MAX(CASE WHEN Param_Name = 'Format' 	 THEN Param_Value END),
    @Extension  = MAX(CASE WHEN Param_Name = 'Extension' THEN Param_Value END),
    @PathOutput = MAX(CASE WHEN Param_Name = 'PathOutput'THEN Param_Value END)
FROM Kustom.dbo.TBL_REG_AUTO_REPORT_PARAMETER WITH(NOLOCK)
WHERE 
		Report_Id = @Report_Id
    AND Exec_Id = @Exec_Id;

-- Reemplazos en nombre del archivo
SET @FileName = REPLACE(@FileName, '#FECHA#', FORMAT(@Exec_Date, 'yyyyMMdd'));
SET @FileName = REPLACE(@FileName, '#REPORT#', @Report_Name);

--Agregar la extension
SET @FileName = @FileName+'.' + @Extension

-- Armar comando final
SET @LinuxCmd =
	
		'ReportBatch REPORT ' + @Report_Name +
		' PARAMS ' + REPLACE(@ParamList, '#FECHA#', FORMAT(@Exec_Date, 'dd/MM/yyyy')) + ' ' +
		@Format + ' ' +
		@PathOutput + @FileName;

-- Devolver valores en tabla
INSERT INTO @RESULT
    (LinuxCmd, PathOutput, FileName)
VALUES
    (@LinuxCmd, @PathOutput, @FileName);
 