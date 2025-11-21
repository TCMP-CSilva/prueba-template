USE Kustom
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_WARNINGS ON
GO
PRINT '<<<<< START CREATING function- Kustom.dbo.FUNC_REG_AUTO_REPORT_GET_LNX_CMD >>>>>' 
IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('FUNC_REG_AUTO_REPORT_GET_LNX_CMD') AND type = 'TF')
BEGIN
PRINT '<<<<< DROP function- Kustom.dbo.FUNC_REG_AUTO_REPORT_GET_LNX_CMD >>>>>' 
	  DROP FUNCTION dbo.FUNC_REG_AUTO_REPORT_GET_LNX_CMD; 
END
GO

CREATE  FUNCTION [dbo].[FUNC_REG_AUTO_REPORT_GET_LNX_CMD] (@Report_Id INT, @Exec_Id INT) 
RETURNS @RESULT TABLE (
						LinuxCmd 	 VARCHAR(MAX),
						PathOutput 	 VARCHAR(256),
						FileName 	 VARCHAR(256)
)
AS
BEGIN 
/*
Descripcion :	Funcion encargada de devolver el comando Linux , Ruta de salida y nombre del fichero requerido por el desarrollo de reportes Automaticos.
Autor		:	Leo Martinez
Fecha		:	2025-09
Empresa		:	TCM PARTNERS
Ejecucion	: 	SELECT dbo.FUNC_REG_AUTO_REPORT_GET_LNX_CMD(@Report_Id, @Exec_Id) ;
Ejemplo		:	
Nota		: 	Se excluyen los acentos dentro de este documento
******************************************************************************************************
Descripcion	:
Autor		:
Fecha		: 
Empresa		: 
*/

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
	;WITH Paramcontrol AS(

		SELECT   Param_Value, 
				 Param_Order
				,ROW_NUMBER() OVER(PARTITION BY Param_Order ORDER BY Exec_Profile) AS RN
		FROM Kustom..TBL_REG_AUTO_REPORT_PARAMETER WITH(NOLOCK)
		WHERE Report_Id = @Report_Id 
		AND Exec_Id = @Exec_Id
		AND Param_Order IS NOT NULL
	
	)
	SELECT @ParamList = 
				STUFF((
						SELECT  '  ' + Param_Value
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
    INSERT INTO @RESULT (LinuxCmd, PathOutput, FileName)
    VALUES (@LinuxCmd, @PathOutput, @FileName);
 
    RETURN;

END
GO 
GRANT SELECT ON dbo.FUNC_REG_AUTO_REPORT_GET_LNX_CMD TO PUBLIC  
GO 
PRINT '<<<<< END CREATING Function - FUNC_REG_AUTO_REPORT_GET_LNX_CMD >>>>>>'  
GO