USE Kustom
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_WARNINGS ON
GO
PRINT '<<<<< START CREATING Stored Procedure - "Kustom.dbo.PRC_CO_OR_Theta_SWP" >>>>>'
GO
IF  EXISTS (SELECT 1 FROM sysobjects where id = object_id(N'dbo.PRC_CO_OR_Theta_SWP') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
	DROP PROCEDURE dbo.PRC_CO_OR_Theta_SWP
	PRINT '<<<<< DROP Stored Procedure - "Kustom.dbo.PRC_CO_OR_Theta_SWP" >>>>>'
GO

CREATE PROCEDURE [dbo].[PRC_CO_OR_Theta_SWP] (@FECHA_T1 DATE)
AS
BEGIN

/*
Descripcion :	Open report encargado de mostrar DV01 y Thetas para Swaps Deals
Autor		:	Leo Martinez
Fecha		:	2025-09
Empresa		:	TCM PARTNERS
Ejecucion	: 	EXEC Kustom..PRC_CO_OR_Theta_SWP '2025-09-09'
Ejemplo		:	
Nota		: 	Se excluyen los acentos dentro de este documento
******************************************************************************************************
Descripcion	:
Autor		:
Fecha		: 
Empresa		: 
*/


--DECLARE @FECHA_T1 DATE = '2025-09-09'

---------------------------------------------------------------------------------------------------
--  V A R I A B L E S     G E N E R A L E S
---------------------------------------------------------------------------------------------------

DECLARE @FECHA_T2	  DATE = (SELECT Kustom.dbo.FUNC_UTIL_Get_DiaHabil (-1, 1, 'CO', (SELECT CONVERT(VARCHAR(8), @FECHA_T1,112))))
DECLARE @PERIMETER_ID INT  = (SELECT TOP 1 Perimeter_Id FROM KplusLocal..RevalPerimeters WITH(NOLOCK) WHERE RevalPerimeters_Name = 'SCOTIABANK_COLOMBIA')

---------------------------------------------------------------------------------------------------
--  D V 0 1 : Inicio
---------------------------------------------------------------------------------------------------

DECLARE @VISTA_DV01 TABLE(
 DealsId			INT  INDEX IX1 CLUSTERED NULL
,Yield_Curves		VARCHAR(32)
,Time_Buck__Curves  VARCHAR(13)
,Leg_Type			CHAR(1)
,Delta				FLOAT
,MarketValuet2		FLOAT
,MarketValuet1		FLOAT
,PyG				FLOAT
);

INSERT INTO @VISTA_DV01(
 DealsId		
,Yield_Curves	
,Time_Buck__Curves
,Leg_Type
,Delta					
,MarketValuet2	
,MarketValuet1
,PyG
)
SELECT 			
 H.DealsId
,H.Yield_Curves
,H.Time_Buck__Curves
,H.LegType
,H.Delta
,CNRH_T2.MarketValue
,CNRH_T1.MarketValue
,CASE WHEN CR.CurvesRatesUnderlying ='R' THEN (H.Delta * (CNRH_T1.MarketValue - CNRH_T2.MarketValue)*100) ELSE H.Delta * (CNRH_T1.MarketValue - CNRH_T2.MarketValue) END
	
FROM DataKondorCO..TBL_DRV_RPT_RK_DGIR_MQ_HIST H WITH (NOLOCK)
INNER JOIN KplusLocal..SwapDeals AS S WITH(NOLOCK)
	ON  H.Fecha = @FECHA_T2
    AND ABS(H.Delta) >= 0.00001
	AND S.TypeOfEvent != 'L' --Descartar liquidaciones T1,Tn
	AND @FECHA_T2 > CAST(S.CaptureDate AS DATE)--Descartar Capturados T1, T2
	AND H.DealsId = S.SwapDeals_Id	
INNER JOIN KplusLocal..SwapLeg SL WITH (NOLOCK)
		ON  S.SwapDeals_Id = SL.SwapDeals_Id
		AND H.LegType = SL.LegType
		AND SL.MaturityDate > = @FECHA_T1 --Descartar vencimientos
INNER JOIN KplusLocal..Curves C WITH (NOLOCK)
	ON H.Yield_Curves = C.Curves_ShortName
INNER JOIN KplusLocal..CurvesRatesNR CR WITH (NOLOCK)
    ON C.Curves_Id = CR.Curves_Id
    AND H.Time_Buck__Curves = CR.Tenor

LEFT JOIN KplusLocal..CurvesRatesNRHist CNRH_T1 WITH (NOLOCK)
    ON C.Curves_Id = CNRH_T1.Curves_Id
    AND CR.CurvesTenorsId = CNRH_T1.CurvesTenorsId
    AND CNRH_T1.HistDate = @FECHA_T1
    AND CNRH_T1.Perimeter_Id = @PERIMETER_ID

LEFT JOIN KplusLocal..CurvesRatesNRHist CNRH_T2 WITH (NOLOCK)
    ON C.Curves_Id = CNRH_T2.Curves_Id
    AND CR.CurvesTenorsId = CNRH_T2.CurvesTenorsId
    AND CNRH_T2.HistDate = @FECHA_T2
    AND CNRH_T2.Perimeter_Id = @PERIMETER_ID

--WHERE H.DealsId =55053

--Sumar PyG
DECLARE @PyG_SUM FLOAT

SELECT 
@PyG_SUM = SUM(ISNULL(D.PyG,0)) 
FROM @VISTA_DV01 D

--Listado de Deals DV01 , requerido para filtrar RTK T-1
DECLARE @DV01_DEALS TABLE(
DealsId INT INDEX IX1 CLUSTERED NULL
);

INSERT INTO @DV01_DEALS(
DealsId
)
SELECT DealsId 
FROM @VISTA_DV01 
GROUP BY DealsId

---------------------------------------------------------------------------------------------------
--  D V 0 1 : Fin
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
--  T H E T A : Inicio
---------------------------------------------------------------------------------------------------

--Calcular NPV RTK t1
DECLARE @NPV_RTK_T1 TABLE(
DealNumber INT INDEX IX1 CLUSTERED NULL
,Npv_COP_T1 FLOAT
)
INSERT INTO @NPV_RTK_T1 (
DealNumber,
Npv_COP_T1
)
SELECT 
RTK_T1.SwapDeals_SwapDeals_Id,
SUM(
	ISNULL(
			(RTK_T1.RawPLData_Npv * RTK_T1.ForexRates_FxRateRepCur)
		  ,0)
   )
FROM DataKondorCO.dbo.TBL_DRV_RPT_RTK_SWP_FO_Theta_HIST RTK_T1 WITH (NOLOCK)
INNER JOIN @DV01_DEALS AS DV01
		ON RTK_T1.Fecha = @FECHA_T1
		AND RTK_T1.SwapDeals_SwapDeals_Id = DV01.DealsId
GROUP BY RTK_T1.SwapDeals_SwapDeals_Id

--Calcular NPV RTK t2
DECLARE @NPV_RTK_T2 TABLE(
 DealNumber INT INDEX IX1 CLUSTERED NULL
,MaturityDate DATE
,Npv_COP_T2 FLOAT
)
INSERT INTO @NPV_RTK_T2 (
DealNumber,
MaturityDate,
Npv_COP_T2
)
SELECT
 RTK_T1.DealNumber
,CONVERT(DATE,RTK_T2.MaturityDate , 103)
,SUM(ISNULL(RTK_T2.Npv_COP,0)) 
FROM   @NPV_RTK_T1 RTK_T1 
LEFT JOIN DataKondorCO.dbo.TBL_DRV_RPT_RTK_FX_PROD_SWP_HIST RTK_T2 WITH(NOLOCK)
	ON RTK_T2.Fecha = @FECHA_T2
	AND RTK_T2.SwapDeals_Id = RTK_T1.DealNumber
GROUP BY RTK_T1.DealNumber
		,RTK_T2.MaturityDate

--Calcular y clasificar
DECLARE @DATA_THETA TABLE(
 DealNumber		 INT INDEX IX1 CLUSTERED NULL
,Npv_COP_T1		 FLOAT
,MaturityDate	 DATE
,Npv_COP_T2		 FLOAT
,Theta			 FLOAT
,Dias			 INT
,Categoria		 VARCHAR(20)
,Rango			 VARCHAR(30)
);
WITH RANGOS AS (
    SELECT 1 AS CategoriaNum, 'Categoria 1' AS Categoria, 'MENOR A 30 DIAS' AS Rango, 0 AS Desde, 30 AS Hasta
    UNION ALL
    SELECT 2, 'Categoria 2', 'ENTRE 31 Y 90 DIAS', 31, 90
    UNION ALL
    SELECT 3, 'Categoria 3', 'ENTRE 91 Y 150 DIAS', 91, 150
    UNION ALL
    SELECT 4, 'Categoria 4', 'ENTRE 151 Y 180 DIAS', 151, 180
    UNION ALL
    SELECT 5, 'Categoria 5', 'ENTRE 181 Y 360 DIAS', 181, 360
    UNION ALL
    SELECT 6, 'Categoria 6', 'ENTRE 361 Y 720 DIAS', 361, 720
    UNION ALL
    SELECT 7, 'Categoria 7', 'ENTRE 721 Y 1500 DIAS', 721, 1500
    UNION ALL
    SELECT 8, 'Categoria 8', 'MAYOR A 1500 DIAS', 1501, 99999
)
,CALCULOS AS (
    SELECT 
        NPV_T1.DealNumber,
        NPV_T1.Npv_COP_T1,
        NPV_T2.MaturityDate,
        NPV_T2.Npv_COP_T2,
        (NPV_T1.Npv_COP_T1 - NPV_T2.Npv_COP_T2)  AS Theta,
        ABS(DATEDIFF(DAY, NPV_T2.MaturityDate, @FECHA_T1)) AS Dias
    FROM @NPV_RTK_T1 AS NPV_T1
	INNER JOIN @NPV_RTK_T2 AS NPV_T2
		ON NPV_T1.DealNumber=NPV_T2.DealNumber
)
INSERT INTO @DATA_THETA (
 DealNumber		 
,Npv_COP_T1		 
,MaturityDate	 
,Npv_COP_T2		 
,Theta			 
,Dias			 
,Categoria		 
,Rango			 
)
SELECT 
    B.DealNumber,
    B.Npv_COP_T1,
    B.MaturityDate,
    B.Npv_COP_T2,
    B.Theta,
    B.Dias,
    R.Categoria,
    R.Rango
FROM CALCULOS B
LEFT JOIN RANGOS R
    ON B.Dias BETWEEN R.Desde AND R.Hasta;

--Agrupar
DECLARE @VISTA_THETA TABLE(
 Rango			 VARCHAR(30)
,Categoria		 VARCHAR(20)
,Theta			 FLOAT
);
INSERT INTO @VISTA_THETA(
 Rango
,Categoria
,Theta
)
SELECT   
		 Rango
		,Categoria
		,SUM(Theta)
FROM @DATA_THETA
GROUP BY Rango
		,Categoria
			
---------------------------------------------------------------------------------------------------
--  T H E T A : Fin
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
--							O U T P U T   O P E N  R E P O R T 
---------------------------------------------------------------------------------------------------
--1.
SELECT __ELEM_TITLE__ =  'DV01'
SELECT __HEADER__     =                          
						
						 'Deal'
						,'Yield Curve'
						,'Tenor Curva'
						,'Leg Type'
						,'DVO1'
						,'Valor curva T-2'
						,'Valor curva T-1'
						,'P&G Sensibilidad'
						

SELECT __FORMAT__     =
								
						 NULL
						,NULL
						,NULL
						,NULL
						,'999 999 999 999 999 999.999999'
						,'999 999 999 999 999 999.999999'
						,'999 999 999 999 999 999.999999'
						,'999 999 999 999 999 999.999999'


SELECT 
 X.Col1
,X.Yield_Curves
,X.Time_Buck__Curves
,X.Leg_Type
,X.Delta
,X.MarketValuet2
,X.MarketValuet1
,X.PyG
FROM (
	SELECT 
		 CONVERT(VARCHAR(9), D.DealsId) AS Col1
		,D.Yield_Curves	
		,D.Time_Buck__Curves
		,D.Leg_Type
		,D.Delta					
		,D.MarketValuet2	
		,D.MarketValuet1
		,D.PyG	
		,D.DealsId  AS SortKey  -- Usado para ordenar DealId como numero
	FROM @VISTA_DV01 D
 
	UNION ALL
 
	SELECT 
		 'Total' AS Col1
		,NULL,NULL,NULL,NULL,NULL,NULL,ISNULL(@PyG_SUM,0)
		,999999999  -- Forzamos el Total al final con un valor alto
) AS X
ORDER BY SortKey;


--2.---------------------------------------------------------------------------------------------------
SELECT __ELEM_TITLE__ = 'Theta Details' 
SELECT __HEADER__     =
						 'Deal'
						,'RTK T-2'
						,'RTK T-1'
						,'Theta'
						,'Maturity Date'
						,'Dias'
						,'Categoria'
						,'Rango'
						
SELECT __FORMAT__     =	
						 NULL
						,'999 999 999 999 999 999.99'
						,'999 999 999 999 999 999.99'
						,'999 999 999 999 999 999.99'
						,NULL
						,NULL
						,NULL
						,NULL
						
SELECT 
						 D.DealNumber		
						,D.Npv_COP_T2
						,D.Npv_COP_T1		
						,D.Theta			
						,D.MaturityDate	
						,D.Dias			
						,D.Categoria		
						,D.Rango			
						
FROM  @DATA_THETA	D
ORDER BY D.DealNumber

--3.---------------------------------------------------------------------------------------------------
SELECT __ELEM_TITLE__ = 'Theta' 
SELECT __HEADER__     =
						 'RANGO'
						,'CATEGORIA'
						,'THETA'
						
SELECT __FORMAT__     =	
						 NULL
						,NULL
						,'999 999 999 999 999 999.99'
						
SELECT 
						 Rango
						,Categoria
						,Theta
						
FROM @VISTA_THETA	T


--4.---------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------
-- Calcular Vencimientos : Inicio
--------------------------------------------------------------------------
-- Obtener FxRateRepCur en RTK-T2 para convertir el Casflow-T2 a COP
DECLARE @EXCHANGE_RATES TABLE (
CurrencyShortName VARCHAR(32),
FxRateRepCur FLOAT
);
INSERT INTO @EXCHANGE_RATES (
CurrencyShortName,
FxRateRepCur
)
SELECT DISTINCT
CurrencyShortName, 
FxRateRepCur

FROM   @NPV_RTK_T1 RTK_T1 
LEFT JOIN DataKondorCO.dbo.TBL_DRV_RPT_RTK_FX_PROD_SWP_HIST RTK_T2 WITH(NOLOCK)
	ON RTK_T2.Fecha = @FECHA_T2
	AND RTK_T2.SwapDeals_Id = RTK_T1.DealNumber

--Calcular Casflow CFER t2 a COP
DECLARE @VENCIMIENTOS TABLE(
 DealNumber INT
,Cashflow_COP FLOAT
)
INSERT INTO @VENCIMIENTOS (
DealNumber
,Cashflow_COP
)
SELECT 
  T1.DealNumber
,SUM (
	   ISNULL(
				(CFER_T2.Deal_Cashflow * ER.FxRateRepCur)
			,0)
	)
FROM  @NPV_RTK_T1 T1
LEFT JOIN DataKondorCO..TBL_DRV_RPT_CFER_FX_PROD_Detail_Hist AS CFER_T2 WITH (NOLOCK)
	ON  CFER_T2.Fecha = @FECHA_T2
	AND CFER_T2.DealType = 'IRS'
	AND CFER_T2.PaymentDate = CONVERT(VARCHAR(10), @FECHA_T1, 103)
	AND CFER_T2.DealNumber = T1.DealNumber
LEFT JOIN @EXCHANGE_RATES ER
	ON ER.CurrencyShortName = CASE WHEN CFER_T2.Deal_Cur_Pair IS NULL THEN CFER_T2.Deal_Pp_Ccy ELSE CFER_T2.Deal_Cur_Pair END
GROUP BY T1.DealNumber
--------------------------------------------------------------------------
-- Calcular Vencimientos : Fin
--------------------------------------------------------------------------
-- Calcular P&G Sensibilidad por Deal	
DECLARE @ACUM_PYG_DV01 TABLE(
 DealsId INT
,PyG FLOAT
)
INSERT @ACUM_PYG_DV01(
 DealsId
,PyG
) 
SELECT 
	D.DealsId, 
	SUM(D.PyG)
FROM @VISTA_DV01 D
GROUP BY
	D.DealsId

--Salida vista
SELECT __ELEM_TITLE__ =  'Flash PnL'
SELECT __HEADER__     =                          
						
						 'Deal ID'
						,'P&G Sensibilidad'
						,'Theta'
						,'Vencimientos'
						,'Total'
						
SELECT __FORMAT__     =	
						 NULL
						,'999 999 999 999 999 999.99'
						,'999 999 999 999 999 999.99'
						,'999 999 999 999 999 999.99'
						,'999 999 999 999 999 999.99'					

;WITH VISTAFLASHPNL AS (
	SELECT 
		 D.DealsId,
		 D.PyG,
		 ISNULL(T.Theta,0)AS Theta,
		 ISNULL(V.Cashflow_COP,0)AS Vencimientos
	FROM @ACUM_PYG_DV01 D
	INNER JOIN @DATA_THETA T
		ON D.DealsId = T.DealNumber
	INNER JOIN @VENCIMIENTOS V
		ON D.DealsId = V.DealNumber
)
SELECT
	 FPNL.DealsId
	,FPNL.PyG
	,FPNL.Theta
	,FPNL.Vencimientos
	,FPNL.PyG + FPNL.Theta + FPNL.Vencimientos AS Total
	
FROM VISTAFLASHPNL FPNL
ORDER BY FPNL.DealsId;


END
GO
GRANT EXECUTE ON Kustom.dbo.PRC_CO_OR_Theta_SWP TO PUBLIC  
GO
PRINT '<<<<< END CREATING Stored Procedure - "Kustom.dbo.PRC_CO_OR_Theta_SWP" >>>>>'