USE Kustom
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_WARNINGS ON
GO
PRINT '<<<<< START CREATING Stored Procedure - "Kustom.dbo.PRC_CO_OR_RK_MQT1H_Swps" >>>>>'
GO
IF  EXISTS (SELECT * FROM sysobjects where id = object_id(N'dbo.PRC_CO_OR_RK_MQT1H_Swps') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
	DROP PROCEDURE dbo.PRC_CO_OR_RK_MQT1H_Swps
	PRINT '<<<<< DROP Stored Procedure - "Kustom.dbo.PRC_CO_OR_RK_MQT1H_Swps" >>>>>'
GO
CREATE PROCEDURE [dbo].[PRC_CO_OR_RK_MQT1H_Swps] ( @FechaConsulta DATETIME = NULL) 
AS
BEGIN

/*
Descripcion :	Open Report RK CO_RK_MQ_T1
Autor		:	Leo Martinez
Fecha		:	2024-04
Empresa		:	TCM PARTNERS
Ejecucion	: 	EXEC Kustom..PRC_CO_OR_RK_MQT1H_Swps '2025-04-08'
Nota		: 	Se excluyen los acentos dentro de este documento
******************************************************************************************************
Descripcion	:	Se excluyen los registros cuya magnitud(ABS)de sus Deltas sea menor a 0.00001 , tenors que no deberian mostrarse.
Autor		:	Leo Martinez
Fecha		:	2024-04
Empresa		:	TCM PARTNERS
Tag			:	LM_20250610
*/

IF @FechaConsulta = '1900/01/01' OR @FechaConsulta IS NULL 
	BEGIN
		SET @FechaConsulta = CONVERT(DATETIME,( SELECT Kustom.dbo.FUNC_UTIL_Get_DiaHabil (-1, 1, 'CO', (SELECT CONVERT(VARCHAR(8),GETDATE(),112)))))
	END

DECLARE @COP INT
SELECT @COP = Currencies_Id FROM KplusLocal..Currencies WITH(NOLOCK)  WHERE Currencies_ShortName IN ('COP')

------------------------------------------------
--			S W A P S  D E A L S
------------------------------------------------

IF OBJECT_ID('tempdb..#TEMPDETALLE_AUX_SWPDRV') IS NOT NULL
BEGIN
	DROP TABLE #TEMPDETALLE_AUX_SWPDRV;
END
 
CREATE TABLE #TEMPDETALLE_AUX_SWPDRV (
 Fecha					date	
,DealType				varchar(46)
,Yield_Curves			varchar(46)
,Time_Buck__Curves		varchar(46)
,BranchPF				varchar(10)
,BranchFF				varchar(10)
,DealsId				int	
,LegType				varchar(46)
,TypeOfInstrument		varchar(10)
,Currencies_ShortName   varchar(46)
,Delta					float
,DeltaCO				float
,PositionFolder			varchar(20)
,Currencies_Id			int
)

CREATE INDEX IX_Fecha				ON #TEMPDETALLE_AUX_SWPDRV (Fecha);
CREATE INDEX IX_DealType			ON #TEMPDETALLE_AUX_SWPDRV (DealType);
CREATE INDEX IX_Time_Buck__Curves	ON #TEMPDETALLE_AUX_SWPDRV (Time_Buck__Curves);
CREATE INDEX IX_BranchPF			ON #TEMPDETALLE_AUX_SWPDRV (BranchPF);
CREATE INDEX IX_BranchFF			ON #TEMPDETALLE_AUX_SWPDRV (BranchFF);
CREATE INDEX IX_DealsId				ON #TEMPDETALLE_AUX_SWPDRV (DealsId);
CREATE INDEX IX_LegType				ON #TEMPDETALLE_AUX_SWPDRV (LegType);
CREATE INDEX IX_TypeOfInstrument	ON #TEMPDETALLE_AUX_SWPDRV (TypeOfInstrument);

INSERT INTO #TEMPDETALLE_AUX_SWPDRV
(
 Fecha				
,DealType			
,Yield_Curves		
,Time_Buck__Curves	
,BranchPF			
,BranchFF			
,DealsId			
,LegType			
,TypeOfInstrument	
,Currencies_ShortName  
,Delta				
,DeltaCO			
,PositionFolder		
,Currencies_Id		
)
SELECT  
 H.Fecha			
,H.DealType		
,H.Yield_Curves	
,H.Time_Buck__Curves
,BPF.Branches_ShortName 			
,BFF.Branches_ShortName 
,H.DealsId 
,H.LegType 
,H.TypeOfInstrument 
,H.Currencies_ShortName
,H.Delta 
,H.Delta 
,H.PositionFolder 			
,H.Currencies_Id 
FROM 	   DataKondorCO..TBL_DRV_RPT_RK_DGIR_MQ_HIST H WITH(NOLOCK)
INNER JOIN Kustom..TBL_REG_SCOTIAZONE_HIERARCHY PF WITH(NOLOCK) 
 ON		   H.Fecha= @FechaConsulta
 AND       ABS(H.Delta) > = 0.00001 --LM_20250610
 AND 	   PF.Folders_ShortName = H.PositionFolder			
INNER JOIN KplusLocal..Branches BPF WITH(NOLOCK) 
 ON 	   BPF.Branches_Id = PF.Branches_Id 			
INNER JOIN Kustom..TBL_REG_SCOTIAZONE_HIERARCHY FF WITH(NOLOCK) 
 ON        FF.Folders_ShortName = H.Folder 			
INNER JOIN KplusLocal..Branches BFF WITH(NOLOCK) 
 ON        BFF.Branches_Id = FF.Branches_Id 
 
 ------------------------------------------------
 --  M O N E D A S
 ------------------------------------------------
DECLARE @TEMPMONEDASDRV TABLE(
 Currencies_Id INT
,Currencies_ShortName varchar(46)
,SpotRate FLOAT
)
INSERT INTO  @TEMPMONEDASDRV(
 Currencies_Id
,Currencies_ShortName
,SpotRate
)
SELECT
 Currencies_Id
,Currencies_ShortName
,0					
FROM #TEMPDETALLE_AUX_SWPDRV
GROUP BY Currencies_Id
		,Currencies_ShortName

 ------------------------------------------------
 --  E X P R E S I O N  M O N E D A S  A  C O P 
 ------------------------------------------------
UPDATE @TEMPMONEDASDRV			
SET	SpotRate=  Kustom.dbo.FUNC_CO_GET_AMOUNT_CCY_DAY(1, Currencies_Id, @COP, @FechaConsulta)			

 ------------------------------------------------
 -- D E L T A  C O 
 ------------------------------------------------
UPDATE TD			
SET	DeltaCO = (Delta * SpotRate)
FROM #TEMPDETALLE_AUX_SWPDRV TD			
INNER JOIN @TEMPMONEDASDRV TM			
ON TD.Currencies_ShortName <>'COP'	
AND TD.Currencies_Id = TM.Currencies_Id 		

------------------------------------------------
--   R E S U M E N  F I N A L 
------------------------------------------------
IF OBJECT_ID('tempdb..#TEMPRESUMEN_FINAL_SWPDRV') IS NOT NULL
BEGIN
	DROP TABLE #TEMPRESUMEN_FINAL_SWPDRV;
END

CREATE TABLE #TEMPRESUMEN_FINAL_SWPDRV(
 Fecha						date
,DealType					varchar(46)
,Yield_Curves				varchar(46)
,Time_Buck__Curves			varchar(46)
,BranchPF					varchar(10)
,PositionFolder				varchar(20)
,BranchFF					varchar(10)
,DealsId					int
,LegType_Nemo				varchar(46)
,TypeOfInstrument_ISINCode	varchar(10)
,Currencies_ShortName		varchar(46)
,SumaDelta					float
,SumaDeltaCO				float
)

INSERT INTO #TEMPRESUMEN_FINAL_SWPDRV (
 Fecha					
,DealType				
,Yield_Curves			
,Time_Buck__Curves		
,BranchPF				
,PositionFolder			
,BranchFF				
,DealsId				
,LegType_Nemo			
,TypeOfInstrument_ISINCode
,Currencies_ShortName	
,SumaDelta				
,SumaDeltaCO			
)
SELECT 
 Fecha 
,DealType
,Yield_Curves
,Time_Buck__Curves
,BranchPF
,PositionFolder
,BranchFF
,DealsId 
,LegType 
,TypeOfInstrument
,Currencies_ShortName
,Delta
,DeltaCO
FROM #TEMPDETALLE_AUX_SWPDRV H			
ORDER BY Fecha, H.DealType, Time_Buck__Curves, BranchPF, BranchFF, DealsId , LegType, TypeOfInstrument			


---------------------------------------------------------------------------------------------------
--							O U T P U T   O P E N  R E P O R T 
---------------------------------------------------------------------------------------------------
	SELECT __ELEM_TITLE__ = 'Delta de Interest Rate'
	SELECT __HEADER__     =
							 'Fecha'
							,'DealType'
							,'Yield_Curves'
							,'Time_Buck__Curves'
							,'BranchPF'
							,'PositionFolder'
							,'BranchFF'
							,'DealsId'
							,'LegType'
							,'TypeOfInstrument'
							,'Currencies_ShortName'
							,'Delta'
							,'DeltaCO'
	SELECT __FORMAT__     =	
							 NULL
							,NULL
							,NULL
							,NULL
							,NULL
							,NULL
							,NULL
							,NULL
							,NULL
							,NULL
							,NULL
							,'999 999 999 999 999 999.99'
							,'999 999 999 999 999 999.99'

	SELECT 			
						    Fecha
						   ,DealType
						   ,Yield_Curves
						   ,Time_Buck__Curves
						   ,BranchPF
						   ,PositionFolder
						   ,BranchFF
						   ,DealsId		
						   ,LegType_Nemo
						   ,TypeOfInstrument_ISINCode
						   ,Currencies_ShortName
						   ,SumaDelta
						   ,SumaDeltaCO
						   
	FROM #TEMPRESUMEN_FINAL_SWPDRV


END
GO
GRANT EXECUTE ON Kustom.dbo.PRC_CO_OR_RK_MQT1H_Swps TO PUBLIC  
GO
PRINT '<<<<< END CREATING Stored Procedure - "Kustom.dbo.PRC_CO_OR_RK_MQT1H_Swps" >>>>>' 