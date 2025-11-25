USE Kustom
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_WARNINGS ON
GO
PRINT '<<<<< START CREATING Stored Procedure - "Kustom.dbo.PRC_PE_DRV_ANEXO08" >>>>>'
GO
IF  EXISTS (SELECT 1 FROM sysobjects where id = object_id(N'dbo.PRC_PE_DRV_ANEXO08') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
	DROP PROCEDURE dbo.PRC_PE_DRV_ANEXO08
	PRINT '<<<<< DROP Stored Procedure - "Kustom.dbo.PRC_PE_DRV_ANEXO08" >>>>>'
GO
CREATE PROCEDURE [dbo].[PRC_PE_DRV_ANEXO08] (@FECHAEJECUCION DATETIME = NULL
											,@AnexoId VARCHAR(1))
AS
BEGIN 

/*
Descripcion	: 	Informacion de las tablas informativas del Anexo 8 (A y B).
Autor		: 	Juan Durand
Fecha		: 	2021-01
Empresa		: 	TCM Partners select * from KplusLocal..ForwardDeals where ForwardDeals_Id = 864073
Ejecucion	: 	EXEC Kustom.dbo.PRC_PE_DRV_ANEXO08 '@FECHAEJECUCION','@AnexoId'
Ejemplo		: 	EXEC Kustom.dbo.PRC_PE_DRV_ANEXO08 '20221124' ,'A'
					EXEC Kustom.dbo.PRC_PE_DRV_ANEXO08 '20221109' ,'B'
Nota		: 	Se excluyen las tildes dentro de este documento.
******************************************************************************************************
Descripcion	: Actualizacion del Saldo Contable y MTM
Autor		: Juan Durand
Fecha Actualizacion : 2021-06-01
Empresa		: TCM Partners
******************************************************************************************************
Descripcion	: Actualizacion del MTM con fechas feriados, codigo BT y cartera
Autor		: Juan Durand
Fecha Actualizacion : 2021-07-01
Empresa		: TCM Partners
******************************************************************************************************
Descripcion	: Se creo dos tablas temporales para evitar el sobreproceso en el bloque Select del query 
			  Operaciones a Futuro con M.E.
Autor		: Eder Ortega
Fecha Actualizacion : 2023-06-30
Empresa		: TI Local
*******************************************************************************************************
DESCRIPCION	: Se excluyen operaciones del folder Forward Starting (SAL_FWDSTR) y se agregan los WITH(NOLOCK)
			  faltantes en el SP
AUTOR		: Fredy Miranda (FM202403)
FECHA		: 2024-03
EMPRESA		: TCM Partners
*******************************************************************************************************
DESCRIPCION	: Se actualiza procedimiento para que no se retornen valores negativos para ANEXO08FWDME(FECHA)
			  en la columna Vencimiento Residual
AUTOR		: Victor Perilla (VP202408)
FECHA		: 2024-08
EMPRESA		: TCM Partners
*******************************************************************************************************
DESCRIPCION	:	Para los Fwd se evalua si se le ha hecho evento de TakeUp. Sino tiene TakeUp sin importar si
				tiene OptionDate se mostrara hasta el MaturityDate.
				Pero si tiene TakeUp, se evaluara el MaturityDate del deal asociado para determinar si aparece en el reporte
				Cambio generado por la iniciativa Window Forward, correo Joaquin Adrian Rodriguez, Abril 29 2025.
AUTOR		:	Fredy Miranda
FECHA		:	2025-05
EMPRESA		:	TCM PARTNERS
TAG			:	FM202505
*******************************************************************************************************
DESCRIPCION	: 
			  1. Se agregan 5 columnas a la vista del anexo A de fxo ME - ANEXO8AOPTME
			  -[Precio Valor Actual]
			  -[Tasa de Interes al fijar precio Entregada]
			  -[Tasa de Interes al fijar precio Recibida]
			  -[Tasa de Interes a la fecha del reporte Entregada]
			  -[Tasa de Interes a la fecha del reporte  Recibida]
	
			  2. Se agrega vista anexo B de fxo ME - ANEXO8BOPTME
			  
AUTOR		: Leo Martinez / Guillermo Cangrejo / Joseph Bernardino	
FECHA		: 2025-05	
EMPRESA		: TCM PARTNERS	
TAG			: LM_KONDORG_14011	
*******************************************************************************************************
DESCRIPCION	: Se ajusta el calculo de Gamma y Vega para la vista del anexo A de fxo ME - ANEXO8AOPTME
			  		  
AUTOR		: Leo Martinez / Andres Prieto
FECHA		: 2025-10	
EMPRESA		: TCM PARTNERS	
TAG			: LM_KONDORG_14011_202510	
*******************************************************************************************************
DESCRIPCION	: Se cambia la tabla de la que se toma la informacion para el anexo A y B, dejando ahora como tabla Principal
			  a DataKondorPE..TBL_PE_RTK_FX_HIST.
			  Se realiza ajuste en la logica de moneda pactada.
AUTOR		: Victor Perilla
FECHA		: 2025-11
EMPRESA		: TCM Partners
TAG			: VP_KONDORG_14011_202511
*******************************************************************************************************
*/


/*
DECLARE @FECHAEJECUCION DATETIME = NULL	,@AnexoId VARCHAR(1)
SELECT @FECHAEJECUCION = '20250529'	,@AnexoId = 'B'
*/

DECLARE @USD			INT
		,@PEN 			INT
		,@Regions_Id 	INT
		,@PERU 			INTEGER
		,@Festivo 		INTEGER
		,@DIAHABIL 		DATETIME

SELECT	@USD=Currencies_Id
FROM	KplusLocal..Currencies WITH(NOLOCK)
WHERE	Currencies_ShortName ='USD'

SELECT	@PEN=Currencies_Id
FROM	KplusLocal..Currencies WITH(NOLOCK)
WHERE	Currencies_ShortName ='PEN'

SELECT @Regions_Id = (SELECT TOP 1 Regions_Id FROM Kustom..TBL_REG_SCOTIAZONE_HIERARCHY TBL_H WITH(NOLOCK) WHERE SCOTIAZONE = 'PERU')

SELECT 	@PERU = Cities_Id
FROM 	KplusLocal..Cities WITH(NOLOCK)
WHERE 	Cities_ShortName 		= 'PE'

SELECT  @Festivo =  Kustom.dbo.FUNC_IsHoliday_City(@PERU , @FECHAEJECUCION)
SELECT  @DIAHABIL =	(CASE WHEN @Festivo=0 	THEN @FECHAEJECUCION
											ELSE Kustom.dbo.FUNC_UTIL_Get_DiaHabil (-1, 1, 'PE', CONVERT(VARCHAR,@FECHAEJECUCION,112))
					END)

DECLARE @Pairs TABLE (
CDC					INT
,CP					INT
,Pair_ShortName		VARCHAR(7)
)

INSERT INTO @Pairs
SELECT		CDC.Currencies_Id												'CDC'
			,CP.Currencies_Id												'CP'
			,CONCAT(CDC.Currencies_ShortName,'/',CP.Currencies_ShortName)	'Pair_ShortName'
FROM		DataKondorPE.dbo.TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
INNER JOIN	KplusLocal..Currencies 					CP WITH(NOLOCK)
ON			CP.Currencies_ShortName					= StaticData_PrincipalCurrencySh
INNER JOIN	KplusLocal..Currencies 					CDC WITH(NOLOCK)
ON			CDC.Currencies_ShortName				= DealData_CurrencyShortName
AND			DATEDIFF(DAY,Fecha,@DIAHABIL)		= 0
AND			SwapDeals_SwapDeals_Id 					> 0
AND			SwapLegCurrent_LegType					= 'Loan'

INSERT INTO @Pairs
SELECT		CDC.Currencies_Id												--'CDC'
			,CP.Currencies_Id												--'CP'
			,CONCAT(CDC.Currencies_ShortName,'/',CP.Currencies_ShortName)	--'Pair_ShortName'
FROM		DataKondorPE.dbo.TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
INNER JOIN	KplusLocal..Currencies 					CP WITH(NOLOCK)
ON			CP.Currencies_ShortName					= StaticData_PrincipalCurrencySh
INNER JOIN	KplusLocal..Currencies 					CDC WITH(NOLOCK)
ON			CDC.Currencies_ShortName				= DealData_CurrencyShortName
AND			DATEDIFF(DAY,Fecha,@DIAHABIL)		= 0
AND			SwapDeals_SwapDeals_Id 					> 0
AND			SwapLegCurrent_LegType					= 'Deposit'
AND			CONCAT(CDC.Currencies_ShortName,'/',CP.Currencies_ShortName)	NOT IN (SELECT Pair_ShortName FROM @Pairs)
GROUP BY	CDC.Currencies_Id,CP.Currencies_Id,CDC.Currencies_ShortName,CP.Currencies_ShortName

INSERT INTO @Pairs
SELECT		CDC.Currencies_Id												--'CDC'
			,@PEN														--'CP'
			,CONCAT(CDC.Currencies_ShortName,'/PEN')						--'Pair_ShortName'
FROM		DataKondorPE.dbo.TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
INNER JOIN	KplusLocal..Currencies 					CDC WITH(NOLOCK)
ON			CDC.Currencies_ShortName				= DealData_CurrencyShortName
AND			DATEDIFF(DAY,Fecha,@DIAHABIL)		= 0
AND			SwapDeals_SwapDeals_Id 					> 0
AND			CONCAT(CDC.Currencies_ShortName,'/PEN') NOT IN (SELECT Pair_ShortName FROM @Pairs)
GROUP BY	CDC.Currencies_Id,CDC.Currencies_ShortName

DECLARE @Pairs_TC TABLE (
Currencies_Id_1		INT
,Currencies_Id_2	INT
,Pair_ShortName		VARCHAR(7)
,Tipo_Cambio		DECIMAL(8,4)
)
-- se justifica DISTINCT  linea 185
INSERT INTO @Pairs_TC
SELECT	DISTINCT CDC														'Currencies_Id_1'
				,CP														'Currencies_Id_2'
				,Pair_ShortName
				,Kustom.dbo.FUNC_GET_AMOUNT_CCY_DAY(1, CDC, CP, @DIAHABIL)	'Tipo_Cambio'
FROM @Pairs ORDER BY 1 DESC

DECLARE @Loan TABLE (
SwapDeals_SwapDeals_Id				INT
,RawPLData_Npv_L					DECIMAL(18,2)
,StaticData_PrincipalCurrencySh		VARCHAR(3)
,NoDecimal							INT
,RoundingType						VARCHAR(10)
)

INSERT INTO @Loan
SELECT		SwapDeals_SwapDeals_Id
			,SUM(RawPLData_Npv*TC.Tipo_Cambio) 'RawPLData_Npv_L'
			,StaticData_PrincipalCurrencySh
			,CP.NoDecimal						'NoDecimal'
			,CP.RoundingType					'RoundingType'
FROM		DataKondorPE.dbo.TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
INNER JOIN	KplusLocal..Currencies 					CP WITH(NOLOCK)
ON			CP.Currencies_ShortName					= StaticData_PrincipalCurrencySh
INNER JOIN	KplusLocal..Currencies 					CDC WITH(NOLOCK)
ON			CDC.Currencies_ShortName				= DealData_CurrencyShortName
AND			DATEDIFF(DAY,Fecha,@DIAHABIL)		= 0
AND			SwapDeals_SwapDeals_Id 					> 0
AND			SwapLegCurrent_LegType					= 'Loan'
INNER JOIN	@Pairs_TC 								TC
ON			CONCAT(CDC.Currencies_ShortName,'/',CP.Currencies_ShortName)	= TC.Pair_ShortName
GROUP BY	SwapDeals_SwapDeals_Id,StaticData_PrincipalCurrencySh,CP.NoDecimal,CP.RoundingType


DECLARE @Deposit TABLE (
SwapDeals_SwapDeals_Id				INT
,RawPLData_Npv_D					DECIMAL(18,2)
,StaticData_PrincipalCurrencySh		VARCHAR(3)
,NoDecimal							INT
,RoundingType						VARCHAR(10)
)
--SELECT * FROM DataKondorPE..TBL_PE_RTK_FX_FWD_HIST WHERE Fecha = '2021-10-27'
--select * from KplusArchive..ForwardDealsHist where ForwardDeals_Id = 757445
INSERT INTO @Deposit
SELECT		SwapDeals_SwapDeals_Id
			,SUM(RawPLData_Npv*TC.Tipo_Cambio) 'RawPLData_Npv_D'
			,StaticData_PrincipalCurrencySh
			,CP.NoDecimal						'NoDecimal'
			,CP.RoundingType					'RoundingType'
FROM		DataKondorPE.dbo.TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
INNER JOIN	KplusLocal..Currencies 					CP WITH(NOLOCK)
ON			CP.Currencies_ShortName					= StaticData_PrincipalCurrencySh
INNER JOIN	KplusLocal..Currencies 					CDC WITH(NOLOCK)
ON			CDC.Currencies_ShortName				= DealData_CurrencyShortName
AND			DATEDIFF(DAY,Fecha,@DIAHABIL)		= 0
AND			SwapDeals_SwapDeals_Id 					> 0
AND			SwapLegCurrent_LegType					= 'Deposit'
INNER JOIN	@Pairs_TC 								TC
ON			CONCAT(CDC.Currencies_ShortName,'/',CP.Currencies_ShortName)=TC.Pair_ShortName
GROUP BY SwapDeals_SwapDeals_Id,StaticData_PrincipalCurrencySh,CP.NoDecimal,CP.RoundingType

DECLARE @PENX TABLE(
SwapDeals_SwapDeals_Id	INT
,RawPLData_Npv_PEN		DECIMAL(18,2)
,NoDecimal				INT
,RoundingType			VARCHAR(10)
)

INSERT INTO @PENX
SELECT		SwapDeals_SwapDeals_Id
			,SUM(RawPLData_Npv*TC.Tipo_Cambio) 'RawPLData_Npv_PEN'
			,0									'NoDecimal'
			,'R'								'RoundingType'
FROM		DataKondorPE.dbo.TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
INNER JOIN	KplusLocal..Currencies 					CDC WITH(NOLOCK)
ON			CDC.Currencies_ShortName				= DealData_CurrencyShortName
AND			DATEDIFF(DAY,Fecha,@DIAHABIL)		= 0
AND			SwapDeals_SwapDeals_Id 					> 0
INNER JOIN	@Pairs_TC 								TC
ON			CONCAT(CDC.Currencies_ShortName,'/PEN')	= TC.Pair_ShortName
GROUP BY	SwapDeals_SwapDeals_Id

DECLARE @TBL_PE_MTM_SWAP TABLE(
Fecha_Reporte			DATE
,SwapDeals_Id			INT
,Currencies_ShortName_L	VARCHAR(3)
,MTM_L					DECIMAL(18,2)
,Currencies_ShortName_D	VARCHAR(3)
,MTM_D					DECIMAL(18,2)
,MTM_PEN				DECIMAL(18,2)
)

INSERT INTO @TBL_PE_MTM_SWAP
SELECT		@DIAHABIL
			,A.SwapDeals_SwapDeals_Id			--SwapDeals_SwapDeals_Id
			,L.StaticData_PrincipalCurrencySh	--Currencies_ShortName_L
			,(CASE L.RoundingType
					WHEN 'R' THEN ROUND(L.RawPLData_Npv_L,L.NoDecimal)
					ELSE ROUND (L.RawPLData_Npv_L,L.NoDecimal, 1 )
			END)								--RawPLData_Npv_L
			,D.StaticData_PrincipalCurrencySh	--Currencies_ShortName_D
			,(CASE D.RoundingType
					WHEN 'R' THEN ROUND(D.RawPLData_Npv_D,D.NoDecimal)
					ELSE ROUND (D.RawPLData_Npv_D,D.NoDecimal, 1 )
			END)								--RawPLData_Npv_D
			,(CASE A.RoundingType
					WHEN 'R' THEN ROUND(A.RawPLData_Npv_PEN,A.NoDecimal)
					ELSE ROUND (A.RawPLData_Npv_PEN,A.NoDecimal, 1 )
			END)								--RawPLData_Npv_PEN
FROM 		@PENX 						A
INNER JOIN	@Loan 						L
ON			A.SwapDeals_SwapDeals_Id 	= L.SwapDeals_SwapDeals_Id
INNER JOIN	@Deposit 					D
ON			A.SwapDeals_SwapDeals_Id 	= D.SwapDeals_SwapDeals_Id
ORDER BY 2 ASC

DECLARE @RTK_FWD2_DEALS TABLE (
ForwardDeals_Id	INT
,PosicionInterna	VARCHAR(10)
)

DECLARE @RTK_SWP_DEALS TABLE (
SwapDeals_Id		INT
,InstrumentName	VARCHAR(20)
,PosicionInterna	VARCHAR(10)
)

INSERT INTO @RTK_FWD2_DEALS
SELECT DISTINCT
ForwardDeals_ForwardDeals_Id
,(CASE	WHEN ValuationData_Cpty_ShortName LIKE '[^A-Z]%'
			THEN ''
			ELSE 'Interno'
	END)
FROM 	DataKondorPE.dbo.TBL_PE_RTK_FX_FWD_HIST WITH(NOLOCK) --TBL_PE_RTK_FX_FWD_HIST
WHERE DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0
AND ValuationData_Folder_ShortName != 'SAL_FWDSTR'	--FM202403

--select * from @RTK_FWD_DEALS

INSERT INTO @RTK_SWP_DEALS
SELECT DISTINCT
SwapDeals_SwapDeals_Id
,StaticData_TypeOfInstrShortNam
,(CASE	WHEN StaticData_CptyShortName LIKE '[^A-Z]%'
			THEN ''
			ELSE 'Interno'
	END)
FROM 	DataKondorPE.dbo.TBL_PE_RTK_SWP_HIST WITH(NOLOCK) --TBL_PE_RTK_SWP_HIST
WHERE DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0

IF	(@AnexoId='A')
BEGIN



-----------------------------------------------------------------------

DECLARE @DRVME_PRE1 TABLE(
	ForwardDeals_Id INT
	,VM_Pos_larga				DECIMAL(18,2) NULL
	,Dur_Mac_Pos_larga			DECIMAL(8,4) NULL
	,Dur_Mod_Pos_larga			DECIMAL(8,4) NULL

	,VM_Tasa_Interes			DECIMAL(20,2) NULL
	,TotalSum					DECIMAL(20,2) NULL
	,TIfr_Mon_Recibida			DECIMAL(8,4) NULL

)

INSERT INTO @DRVME_PRE1															
SELECT 
FWD.ForwardDeals_Id
,CONVERT(DECIMAL(18,2), ISNULL( ABS(Npv_Leg_PEN),0))
,CONVERT(DECIMAL(8,4), ISNULL( ABS(ValuationData_Duration),0))
,CONVERT(DECIMAL(8,4), ISNULL( ABS(ValuationData_ModDuration),0))
																									
,CONVERT( DECIMAL(18,2),ISNULL( ABS(Npv_Leg_PEN),0))
,CONVERT( DECIMAL(20,2),ISNULL( ABS(Npv_Leg_PEN),0))
,ISNULL(CONVERT(DECIMAL(8,4),ISNULL( ZeroCouponInterp,0)),0)/100

FROM	
DataKondorPE.dbo.TBL_PE_RTK_FX_FWD_HIST WITH(NOLOCK), 
KplusLocal..ForwardDeals FWD WITH(NOLOCK)																						
WHERE	FWD.ForwardDeals_Id = ForwardDeals_ForwardDeals_Id
AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0
AND		Npv_Leg_PEN>=0
AND		ValuationData_Folder_ShortName != 'SAL_FWDSTR'	--FM202403



-------------------------------------------------------------																			

DECLARE @DRVME_PRE2 TABLE(
	ForwardDeals_Id INT
	,VM_Pos_corta				DECIMAL(18,2) NULL
	,Dur_Mac_Pos_corta			DECIMAL(8,4) NULL
	,Dur_Mod_Pos_corta			DECIMAL(8,4) NULL

	,VM_Tasa_Interes			DECIMAL(20,2) NULL
	,TotalLess					DECIMAL(20,2) NULL

	,TIfr_Mon_Entregada			DECIMAL(8,4) NULL
)

INSERT INTO @DRVME_PRE2															
SELECT 
FWD.ForwardDeals_Id
,CONVERT(DECIMAL(18,2), ISNULL( ABS(Npv_Leg_PEN),0))
,CONVERT(DECIMAL(8,4), ISNULL( ABS(ValuationData_Duration),0))
,CONVERT(DECIMAL(8,4), ISNULL( ABS(ValuationData_ModDuration),0))
																											
,CONVERT( DECIMAL(18,2),ISNULL( ABS(Npv_Leg_PEN),0))
,CONVERT(DECIMAL(20,2),ISNULL( ABS(Npv_Leg_PEN),0))
,ISNULL(CONVERT(DECIMAL(8,4),ISNULL( ZeroCouponInterp,0)),0)/100
FROM	
DataKondorPE.dbo.TBL_PE_RTK_FX_FWD_HIST WITH(NOLOCK), 
KplusLocal..ForwardDeals FWD WITH(NOLOCK)																						
WHERE	FWD.ForwardDeals_Id = ForwardDeals_ForwardDeals_Id
AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0
AND		Npv_Leg_PEN<0
AND		ValuationData_Folder_ShortName != 'SAL_FWDSTR'	--FM202403






DECLARE @DRVME TABLE(
	Cuenta_Contable				VARCHAR(13) NULL
	,Compra_Venta 				VARCHAR(30) NULL
	,Separador_1				VARCHAR(1) NOT NULL
	,Cod_operacion				VARCHAR(35) NULL
	,Saldo_Contable 			DECIMAL(18,2) NULL
	,Moneda_Pactada 			VARCHAR(3) NULL
	,Nominal_Pactado			DECIMAL(18,2) NULL
	,VM_Pos_larga				DECIMAL(18,2) NULL
	,Dur_Mac_Pos_larga			DECIMAL(8,4) NULL
	,Dur_Mod_Pos_larga			DECIMAL(8,4) NULL
	,VM_Pos_corta				DECIMAL(18,2) NULL
	,Dur_Mac_Pos_corta			DECIMAL(8,4) NULL
	,Dur_Mod_Pos_corta			DECIMAL(8,4) NULL
	,Mon_Entregada_oper 		VARCHAR(3) NULL
	,Mon_Recibida_oper			VARCHAR(3) NULL
	,Fec_inicio_oper			DATE NULL
	,Fec_vencimiento_oper		DATE NULL
	,Cpty_Nombre 				VARCHAR(32) NOT NULL
	,Cpty_Residencia			VARCHAR(2) NOT NULL
	,Cpty_Pais					VARCHAR(10) NULL
	,Cpty_Documento				VARCHAR(30) NULL
	,Cpty_YNFinanciero			VARCHAR(3) NOT NULL
	,Cpty_Codigo_SBS			VARCHAR(19) NOT NULL
	,Cpty_Codigo_deudor			VARCHAR(10) NOT NULL
	,Cpty_Pond_venc_residual	DECIMAL(8,6) NULL
	,Cpty_Conv_marco_contra		VARCHAR(1) NOT NULL
	,TC_Spot_Inicial			DECIMAL(18,6) NOT NULL
	,TC_Spot_Fec_reporte		DECIMAL(18,6) NULL
	,TC_Spot_Pactado 			DECIMAL(18,6) NOT NULL
	,VM_Tasa_Interes			DECIMAL(20,2) NULL
	,VM_Tipo_Cambio 			DECIMAL(20,2) NULL
	,VM_Total 					DECIMAL(20,2) NULL
	,Intencion_Contratacion 	VARCHAR(2) NULL
	,Partida_Cubierta 			VARCHAR(32) NOT NULL
	,Porcentaje_Cobertura 		FLOAT NOT NULL
	,Eficacia_Cobertura 		FLOAT NOT NULL
	,Forma_Pago					VARCHAR(12) NOT NULL
	,TIfp_Mon_Entregada			DECIMAL(18,4) NULL
	,TIfp_Mon_Recibida			DECIMAL(18,4) NULL
	,TIfr_Mon_Entregada			DECIMAL(18,4) NULL
	,TIfr_Mon_Recibida			DECIMAL(18,4) NULL
	,Separador_2				VARCHAR(1) NOT NULL
	,Cod_BT						VARCHAR(10) NOT NULL
	,Cod_Cartera 				VARCHAR(30) NULL
)




	/*==============Operaciones a Futuro con M.E.==============*/
INSERT INTO @DRVME
SELECT
	'Cuenta Contable' = 											(CASE	WHEN FWD.Amount1>=0 AND FWD.Amount2<0
																			THEN '7106.01.02.01'
																			ELSE '7206.01.02.02'
																	END)
	,'Por Cada Contrato u Operacion Vigente' = 						(CASE	WHEN FWD.Amount1>=0 AND FWD.Amount2<0
																			THEN 'Forward de Compra'
																			ELSE 'Forward de Venta'
																	END)
	,' ' =															''
	,'Codigo de la operacion' = 									(CASE	WHEN FWD.Amount1>=0 AND FWD.Amount2<0
																			THEN 'FWDC'
																			ELSE 'FWDV'
																	END) +  (CASE 	WHEN LEFT(FWD.DownloadKey,1) <> '#' AND LEFT(FWD.DownloadKey,7) <> 'BLOTTER' AND LEFT(FWD.DownloadKey,10) <> 'PE-FWD-STR'
																					THEN substring(FWD.DownloadKey,len(FWD.DownloadKey)-5,len(FWD.DownloadKey))  /* DK281124 */
																					ELSE CONVERT(VARCHAR,FWD.ForwardDeals_Id) + (CASE	WHEN FWD.ForwardDeals_Id>(SELECT ValorInt FROM Kustom..TBL_PARAMETROS_LOCAL_APP WITH(NOLOCK) WHERE IdGlobal = 'PE_FWD_LAST_ID_95')
																																THEN ''
																																ELSE '95'
																														END)
																	END)
	,'Saldo Contable' = 											CONVERT(DECIMAL(18,2),ISNULL(ABS(FWD.Amount1)*(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1,Cu1.Currencies_Id, @PEN, @FECHAEJECUCION)),0))
	,'Moneda pactada' = 											Cu1.Currencies_ShortName
	,'Monto Nominal Pactado' = 										CONVERT(DECIMAL(18,2),ISNULL(ABS(FWD.Amount1),0))
	--CONVERT(DECIMAL(18,2),ISNULL((CASE	WHEN Cu1.Currencies_ShortName ='PEN'
	--																									THEN ABS(FWD.Amount1)/(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1,Cu1.Currencies_Id, @PEN, @FECHAEJECUCION))
	--																									WHEN Cu2.Currencies_ShortName = 'PEN'
	--																									THEN ABS(FWD.Amount2)/(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1,Cu2.Currencies_Id, @PEN, @FECHAEJECUCION))
	--																									WHEN Cu1.Currencies_ShortName <> 'PEN' AND Cu2.Currencies_ShortName <> 'PEN'
	--																									THEN ABS(FWD.Amount1)
	--																END),0))
	,'Posicion larga a Valor de Mercado' = 							PRE1.VM_Pos_larga
	,'Duracion de Macaulay posicion larga' =                        PRE1.Dur_Mac_Pos_larga
	,'Duracion modificada posicion larga' =                         PRE1.Dur_Mod_Pos_larga
	,'Posicion corta a Valor de Mercado' =                          PRE2.VM_Pos_corta
	,'Duracion de Macaulay posicion corta' =                        PRE2.Dur_Mac_Pos_corta
	,'Duracion modificada posicion corta' =                         PRE2.Dur_Mod_Pos_corta
/*Descripcion de la Operacion*/
	,'Moneda entregada' = 											(CASE	WHEN FWD.Amount1>=0 AND FWD.Amount2<0
																			THEN Cu2.Currencies_ShortName
																			ELSE Cu1.Currencies_ShortName
																	END)
	,'Moneda recibida' = 											(CASE	WHEN FWD.Amount1>=0 AND FWD.Amount2<0
																			THEN Cu1.Currencies_ShortName
																			ELSE Cu2.Currencies_ShortName
																	END)
	,'Fecha de Inicio' = 											CONVERT(DATE,FWD.TradeDate)
	,'Fecha de Vencimiento' = 										CONVERT(DATE,ISNULL(FWD.LiquidationDate,FWD.MaturityDate))


/*Contraparte*/
	,'Nombre' = 													Cy.Cpty_Name
	,'Residente / No Residente' = 									(CASE 	WHEN Cy.IsResident = 'Y'
																			THEN 'R'
																			ELSE 'NR'
																			END)
	,'Pais' = 														(SELECT 	Ci.Cities_ShortName
																				FROM KplusLocal..Cities Ci WITH(NOLOCK)
																				WHERE Cy.Cities_Id = Ci.Cities_Id)
	,'Documento' = 													(CASE	WHEN CyPE.Documento IS NOT NULL
																			THEN CONVERT(VARCHAR,CyPE.Documento)
																			ELSE 'NOSCCATT'
																			END)
	,'Financiero / No Financiero' = 								ISNULL((CASE 	WHEN CyC.CptyClasses_ShortName = 'AFP'
																					THEN 'AFP'
																					WHEN CyC.CptyClasses_ShortName IN ('EMP_BANCAR','EMP_FINANC','SAB','OTRS_EMP_F','BCOS_EXTER','FONDOS_MUT','FONDOS_PUB','SOC_AG_BOL','EMP_ARR_FI')
																					THEN 'F'
																					ELSE 'NF'
																			END),'NF')
	,'Codigo SBS' = 												ISNULL(CyPE.CodigoSBS,0)
	,'Codigo de deudor' = 											 Cy.Cpty_ShortName
	,'Ponderacion por vencimiento residual (riesgo de credito)' = 	(CASE 	WHEN DATEDIFF(DAY,@FECHAEJECUCION,FWD.MaturityDate)>=0 AND DATEDIFF(DAY,@FECHAEJECUCION,FWD.MaturityDate)<=30
																			THEN 2.5
																			WHEN DATEDIFF(DAY,@FECHAEJECUCION,FWD.MaturityDate)>=31 AND DATEDIFF(DAY,@FECHAEJECUCION,FWD.MaturityDate)<=60
																			THEN 4
																			WHEN DATEDIFF(DAY,@FECHAEJECUCION,FWD.MaturityDate)>=61 AND DATEDIFF(DAY,@FECHAEJECUCION,FWD.MaturityDate)<=90
																			THEN 5.25
																			WHEN DATEDIFF(DAY,@FECHAEJECUCION,FWD.MaturityDate)>=91 AND DATEDIFF(DAY,@FECHAEJECUCION,FWD.MaturityDate)<=180
																			THEN 6.75
																			WHEN DATEDIFF(DAY,@FECHAEJECUCION,FWD.MaturityDate)>=181 AND DATEDIFF(DAY,@FECHAEJECUCION,FWD.MaturityDate)<=360
																			THEN 9.5
																			ELSE 12.25
																	END)/100
	,'Convenio marco de contratacion' = 							ISNULL( ( CASE	WHEN CyPE.CM_DRV = 'Y'
																					THEN 'S'
																					ELSE 'N'
																					END),'N')

/*Tipo de Cambio Spot*/
	,'Inicial' = 													ISNULL((CASE 	WHEN FWD.SpotRate = 0
																					THEN 1
																					ELSE FWD.SpotRate
																			END),0) --SpotRate
	,'Al cierre en la fecha de reporte' = 							CONVERT(DECIMAL(18,6),(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1,Cu1.Currencies_Id, @PEN, @FECHAEJECUCION))/(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1,Cu2.Currencies_Id, @PEN, @FECHAEJECUCION)))
	,'Tipo de Cambio Pactado' = 									ISNULL((CASE 	WHEN FWD.ClientFwd = 0
																					THEN 1
																					ELSE FWD.ClientFwd
																			END),0)

/*Valor de Mercado (Valor Actual)*/
	,'Por Tasa de Interes' = 									PRE1.VM_Tasa_Interes - PRE2.VM_Tasa_Interes
																- ISNULL((CONVERT(DECIMAL(17,6),(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1,Cu1.Currencies_Id, @PEN, @FECHAEJECUCION))
																								/(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1,Cu2.Currencies_Id, @PEN, @FECHAEJECUCION))))
																		- ISNULL((CASE 	WHEN FWD.SpotRate = 0
																								THEN 1
																								ELSE FWD.SpotRate
																						END),0),0)
																* (CASE	WHEN FWD.Amount1>=0
																		THEN 1
																		ELSE -1
																	END)
																* 	ABS(FWD.Amount1)	--FM202505
																*	ISNULL((CONVERT(DECIMAL(17,6),(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1,Cu2.Currencies_Id, @PEN, @FECHAEJECUCION)))),0)
	,'Por Tipo de Cambio' =										ISNULL((CONVERT(DECIMAL(17,6),(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1,Cu1.Currencies_Id, @PEN, @FECHAEJECUCION))
																								/(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1,Cu2.Currencies_Id, @PEN, @FECHAEJECUCION))))
																		- ISNULL((CASE 	WHEN FWD.SpotRate = 0
																								THEN 1
																								ELSE FWD.SpotRate
																						END),0),0)
																* (CASE	WHEN FWD.Amount1>=0
																		THEN 1
																		ELSE -1
																	END)
																* 	ABS(FWD.Amount1)	--FM202505
																*	ISNULL((CONVERT(DECIMAL(17,6),(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1,Cu2.Currencies_Id, @PEN, @FECHAEJECUCION)))),0)
	--si es una compra cierre menos inicio, venta inicio menos cierre
	,'Total' =													PRE1.TotalSum - PRE2.TotalLess

	,'Intencion de Contratacion' = 									(CASE 	WHEN LEFT(F.Folders_ShortName,4) = 'TRAD'
																			THEN 'N'
																			WHEN LEFT(F.Folders_ShortName,3) = 'ALM'
																			THEN 'CC'
																	END)
/*Cobertura del Instrumento*/
	,'Partida Cubierta' = 											ISNULL('','')--FWDCob.PARTIDA_CUBIERTA,'')
	,'Porcentaje de cobertura' =                                   	ISNULL(0,0)--FWDCob.PORCENTAJE_COBERTURA,0)
	,'Eficacia de Cobertura' =                                      ISNULL(0,0)--FWDCob.EFICACIA_COBERTURA,0)

	,'Forma de Pago' = 												(CASE	WHEN FWD.ForwardType = 'D'
																			THEN 'Delivery'
																			ELSE 'Sin Delivery'
																	END)

/*Tasas Anuales de Interes Utilizadas al Fijar Precio*/ --Preguntar al usuario
	,'Moneda Entregada' = 											ISNULL(CONVERT(DECIMAL(18,4),(CASE	WHEN FWD.Amount1>=0 AND FWD.Amount2<0
																										THEN FWD.InterestRateCur2
																										ELSE FWD.InterestRateCur1
																								END)),0)/100
	,'Moneda Recibida' = 											ISNULL(CONVERT(DECIMAL(18,4),(CASE	WHEN FWD.Amount1>=0 AND FWD.Amount2<0
																										THEN FWD.InterestRateCur1
																										ELSE FWD.InterestRateCur2
																								END)),0)/100
/*Tasas Anuales de Interes Spot en la fecha de reporte*/
	,'Moneda Entregada' = 											PRE2.TIfr_Mon_Entregada
	,'Moneda Recibida' = 											PRE1.TIfr_Mon_Recibida
	,' ' =															''
	,'Codigo BT' = 													Cy.Cpty_ShortName
	,'Codigo Cartera' = 											(CASE 	WHEN LEFT(FWD.DownloadKey,1) <> '#' AND LEFT(FWD.DownloadKey,7) <> 'BLOTTER' AND LEFT(FWD.DownloadKey,10) <> 'PE-FWD-STR'
																					THEN substring(FWD.DownloadKey,len(FWD.DownloadKey)-5,len(FWD.DownloadKey))  /* DK281124 */
																					ELSE CONVERT(VARCHAR,FWD.ForwardDeals_Id) + (CASE	WHEN FWD.ForwardDeals_Id>(SELECT ValorInt FROM Kustom..TBL_PARAMETROS_LOCAL_APP WITH(NOLOCK) WHERE IdGlobal = 'PE_FWD_LAST_ID_95')
																																THEN ''
																																ELSE '95'
																														END)
																	END)
FROM 		KplusLocal..ForwardDeals FWD WITH(NOLOCK)
INNER JOIN	@RTK_FWD2_DEALS RTKFWD
	ON		FWD.ForwardDeals_Id = RTKFWD.ForwardDeals_Id
INNER JOIN 	KplusLocal..Pairs Pa WITH(NOLOCK)
	ON 			FWD.Pairs_Id = Pa.Pairs_Id
INNER JOIN	KplusLocal..Currencies Cu1 WITH(NOLOCK)
	ON 			Cu1.Currencies_Id = Pa.Currencies_Id_1
INNER JOIN	KplusLocal..Currencies Cu2 WITH(NOLOCK)
	ON 			Cu2.Currencies_Id = Pa.Currencies_Id_2
INNER JOIN	KplusLocal..Folders F WITH(NOLOCK)
	ON 			F.Folders_Id = FWD.Folders_Id
INNER JOIN  Kustom..TBL_REG_SCOTIAZONE_HIERARCHY	TBL_H WITH(NOLOCK)
	ON 			FWD.Folders_Id = TBL_H.Folders_Id
	AND 		TBL_H.Regions_Id = @Regions_Id
INNER JOIN	KplusLocal..TypeOfInstr TY WITH(NOLOCK)
	ON 			FWD.TypeOfInstr_Id = TY.TypeOfInstr_Id
INNER JOIN	KplusLocal..Cpty Cy WITH(NOLOCK)
	ON 			Cy.Cpty_Id = FWD.Cpty_Id
	--AND			(LEFT(TY.TypeOfInstr_ShortName,2) = 'FW' OR LEFT(TY.TypeOfInstr_ShortName,3) = 'FSS')
	AND			FWD.DealStatus		IN ('V')
	AND 		FWD.InputMode		NOT IN	('G')
	AND 		FWD.TypeOfEvent		NOT IN 	('M')
	AND			DATEDIFF(DAY,FWD.TradeDate,@FECHAEJECUCION) >= 0
	AND			DATEDIFF(DAY,IIF(FWD.ForwardType = 'D', FWD.MaturityDate, FWD.LiquidationDate),@FECHAEJECUCION) < 0
	AND			Cy.Folders_Id = 0
LEFT JOIN	Kustom.dbo.TBL_PE_CPTY_CUSTOM	CyPE WITH(NOLOCK)
	ON 			Cy.Cpty_Id = CyPE.DealId
LEFT JOIN	KplusLocal..CptyClasses CyC WITH(NOLOCK)
	ON			CyC.CptyClasses_Id = Cy.CptyClasses_Id
INNER JOIN  @DRVME_PRE1 PRE1 ON PRE1.ForwardDeals_Id = FWD.ForwardDeals_Id
INNER JOIN  @DRVME_PRE2 PRE2 ON PRE2.ForwardDeals_Id = FWD.ForwardDeals_Id
-- Inicio : FM202505
LEFT JOIN KplusLocal..ForwardDeals TKU WITH(NOLOCK)
ON FWD.ForwardDeals_Id = TKU.ForwardDeals_Id_Father
AND TKU.TypeOfEvent = 'T'
WHERE DATEDIFF(DAY,ISNULL(TKU.MaturityDate,CASE WHEN FWD.ForwardType = 'D' THEN FWD.MaturityDate ELSE FWD.LiquidationDate END),@FECHAEJECUCION) < 0  
-- Fin : FM202505
	ORDER BY 2 ASC


/*SWAP*/
INSERT INTO @DRVME
SELECT
	'Cuenta Contable' = 											(CASE	WHEN (CULP.Currencies_ShortName = 'PEN')
																			AND	 (CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
																			THEN '7206.01.01.02'
																			WHEN (CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
																			AND	 (CUDP.Currencies_ShortName = 'PEN')
																			THEN '7106.01.01.01'
																			WHEN (CULP.Currencies_ShortName = 'USD')
																			AND	 (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP'))
																			THEN '7206.01.01.02'
																			WHEN (CULP.Currencies_ShortName IN ('EUR','JPY','GBP'))
																			AND	 (CUDP.Currencies_ShortName = 'USD')
																			THEN '7106.01.01.01'
																	END)
	,'Por Cada Contrato u Operacion Vigente' = 						(CASE	WHEN (CULP.Currencies_ShortName = 'PEN')
																			AND	 (CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
																			THEN 'Venta Swaps'
																			WHEN (CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
																			AND	 (CUDP.Currencies_ShortName = 'PEN')
																			THEN 'Compra Swaps'
																			WHEN (CULP.Currencies_ShortName = 'USD')
																			AND	 (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP'))
																			THEN 'Venta Swaps'
																			WHEN (CULP.Currencies_ShortName IN ('EUR','JPY','GBP'))
																			AND	 (CUDP.Currencies_ShortName = 'USD')
																			THEN 'Compra Swaps'
																	END)
	,' ' =															''
	,'Codigo de la operacion' = 									(CASE	WHEN (CULP.Currencies_ShortName = 'PEN')
																			AND	 (CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
																			THEN 'SWAPV'
																			WHEN (CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
																			AND	 (CUDP.Currencies_ShortName = 'PEN')
																			THEN 'SWAPC'
																			WHEN (CULP.Currencies_ShortName = 'USD')
																			AND	 (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP'))
																			THEN 'SWAPV'
																			WHEN (CULP.Currencies_ShortName IN ('EUR','JPY','GBP'))
																			AND	 (CUDP.Currencies_ShortName = 'USD')
																			THEN 'SWAPC'
																	END) + (CASE 	WHEN LEFT(SWP.DownloadKey,1) <> '#'
																					THEN RIGHT(SWP.DownloadKey,5)
																					ELSE CONVERT(VARCHAR,SWP.SwapDeals_Id)
																			END)
	,'Saldo Contable' = 											CONVERT(DECIMAL(18,2),ISNULL((CASE	WHEN (CULP.Currencies_ShortName = 'PEN')
																										AND	 (CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
																										THEN	(SELECT TOP 1 SWS.Principal * (CASE WHEN SWS.PrincipalFXRate = 0
																																					THEN 1
																																					ELSE SWS.PrincipalFXRate
																																				END)
																													FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																													WHERE 	SWS.SwapDeals_Id = SWD.SwapDeals_Id
																													AND		SWS.ScheduleLeg = SWD.LegType
																													AND		SWS.CashFlowType = 'I'
																													AND		SWS.PeriodType = 'P'
																													AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																													ORDER BY SWS.EndDate ASC)*(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType)), @PEN, @FECHAEJECUCION))
																										WHEN (CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
																										AND	 (CUDP.Currencies_ShortName = 'PEN')
																										THEN	(CASE 	WHEN TY.TypeOfInstr_ShortName = 'SC'
																														THEN SWD.PrincipalAmount
																														ELSE (SELECT TOP 1 SWS.Principal * (CASE 	WHEN SWS.PrincipalFXRate = 0
																																									THEN 1
																																									ELSE SWS.PrincipalFXRate
																																								END)
																																FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																WHERE 	SWS.SwapDeals_Id = SWD.SwapDeals_Id
																																AND		SWS.ScheduleLeg = SWD.LegType
																																AND		SWS.CashFlowType = 'I'
																																AND		SWS.PeriodType = 'P'
																																AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																													ORDER BY SWS.EndDate ASC)
																												END)
																										WHEN (CULP.Currencies_ShortName = 'USD')
																										AND	 (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP'))
																										THEN	(SELECT TOP 1 SWS.Principal* (CASE 	WHEN SWS.PrincipalFXRate = 0
																																					THEN 1
																																					ELSE SWS.PrincipalFXRate
																																				END)
																													FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																													WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																													AND		SWS.ScheduleLeg = SWL.LegType
																													AND		SWS.CashFlowType = 'I'
																													AND		SWS.PeriodType = 'P'
																													AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																													ORDER BY SWS.EndDate ASC)*(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)), @PEN, @FECHAEJECUCION))
																										WHEN (CULP.Currencies_ShortName IN ('EUR','JPY','GBP'))
																										AND	 (CUDP.Currencies_ShortName = 'USD')
																										THEN	(SELECT TOP 1 SWS.Principal* (CASE 	WHEN SWS.PrincipalFXRate = 0
																																					THEN 1
																																					ELSE SWS.PrincipalFXRate
																																				END)
																																FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																WHERE 	SWS.SwapDeals_Id = SWD.SwapDeals_Id
																																AND		SWS.ScheduleLeg = SWD.LegType
																																AND		SWS.CashFlowType = 'I'
																																AND		SWS.PeriodType = 'P'
																																AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																													ORDER BY SWS.EndDate ASC)* (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType)), @PEN, @FECHAEJECUCION))
																								END),0))
	,'Moneda pactada' = 											(CASE	WHEN (CULP.Currencies_ShortName = 'PEN')
																			AND	 (CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
																			THEN CUDP.Currencies_ShortName
																			WHEN (CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
																			AND	 (CUDP.Currencies_ShortName = 'PEN')
																			THEN CULP.Currencies_ShortName
																			WHEN (CULP.Currencies_ShortName = 'USD')
																			AND	 (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP'))
																			THEN CUDP.Currencies_ShortName
																			WHEN (CULP.Currencies_ShortName IN ('EUR','JPY','GBP'))
																			AND	 (CUDP.Currencies_ShortName = 'USD')
																			THEN CULP.Currencies_ShortName
																	END)
	,'Monto Nominal Pactado' = 										CONVERT(DECIMAL(18,2),ISNULL((CASE	WHEN ((CULP.Currencies_ShortName = 'PEN')
																										AND	 ((CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))))
																										OR	((CULP.Currencies_ShortName = 'USD')
																										AND	 (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP')))
																										THEN	(SELECT TOP 1 SWS.Principal
																													FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																													WHERE 	SWS.SwapDeals_Id = SWD.SwapDeals_Id
																													AND		SWS.ScheduleLeg = SWD.LegType
																													AND		SWS.CashFlowType = 'I'
																													AND		SWS.PeriodType = 'P'
																													AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																													ORDER BY SWS.EndDate ASC)
																										WHEN ((CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
																										AND	 (CUDP.Currencies_ShortName = 'PEN'))
																										OR	((CULP.Currencies_ShortName IN ('EUR','JPY','GBP'))
																										AND	 (CUDP.Currencies_ShortName = 'USD'))
																										THEN	(CASE 	WHEN TY.TypeOfInstr_ShortName = 'SC'
																														THEN SWL.PrincipalAmount
																														ELSE (SELECT TOP 1 SWS.Principal
																																FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																																AND		SWS.ScheduleLeg = SWL.LegType
																																AND		SWS.CashFlowType = 'I'
																																AND		SWS.PeriodType = 'P'
																																AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																													ORDER BY SWS.EndDate ASC)
																												END)
																								END),0))
	,'Posicion larga a Valor de Mercado' = 									 CONVERT(DECIMAL(18,2), (CASE 	WHEN (CULP.Currencies_ShortName = 'USD')
																											THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)), @PEN, @DIAHABIL))
																											ELSE 1
																											END) * ISNULL( ABS((SELECT 	MTM_L
																																		FROM	@TBL_PE_MTM_SWAP MTMSWP
																																		WHERE 	MTMSWP.SwapDeals_Id = SWL.SwapDeals_Id
																																		AND		DATEDIFF ( DAY, MTMSWP.Fecha_Reporte, @DIAHABIL) = 0)),0))
	,'Duracion de Macaulay posicion larga' =                                CONVERT(DECIMAL(8,4),ISNULL( ABS((SELECT 	SUM(RiskData_Duration)
																											FROM 	DataKondorPE..TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
																											WHERE	SwapDeals_SwapDeals_Id = SWL.SwapDeals_Id
																											AND		LEFT(SwapLegCurrent_LegType,1) = 'L'
																											AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0)),0))
	,'Duracion modificada posicion larga' =                                 CONVERT(DECIMAL(8,4),ISNULL( ABS((SELECT 	SUM(RiskData_ModDuration)
																											FROM 	DataKondorPE..TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
																											WHERE	SwapDeals_SwapDeals_Id = SWL.SwapDeals_Id
																											AND		LEFT(SwapLegCurrent_LegType,1) = 'L'
																											AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0)),0))
	,'Posicion corta a Valor de Mercado' =                                 CONVERT(DECIMAL(18,2), (CASE 	WHEN (CUDP.Currencies_ShortName = 'USD')
																											THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType)), @PEN, @DIAHABIL))
																											ELSE 1
																											END) * ISNULL( ABS((SELECT 	MTM_D
																																		FROM	@TBL_PE_MTM_SWAP MTMSWP
																																		WHERE 	MTMSWP.SwapDeals_Id = SWD.SwapDeals_Id
																																		AND		DATEDIFF ( DAY, MTMSWP.Fecha_Reporte, @DIAHABIL) = 0)),0))
	,'Duracion de Macaulay posicion corta' =                                CONVERT(DECIMAL(8,4),ABS(ISNULL( (SELECT 	SUM(RiskData_Duration)
																											FROM 	DataKondorPE..TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
																											WHERE	SwapDeals_SwapDeals_Id = SWL.SwapDeals_Id
																											AND		LEFT(SwapLegCurrent_LegType,1) = 'D'
																											AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0),0)))
	,'Duracion modificada posicion corta' =                                 CONVERT(DECIMAL(8,4),ABS(ISNULL( (SELECT 	SUM(RiskData_ModDuration)
																											FROM 	DataKondorPE..TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
																											WHERE	SwapDeals_SwapDeals_Id = SWL.SwapDeals_Id
																											AND		LEFT(SwapLegCurrent_LegType,1) = 'D'
																											AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0),0)))
/*Descripcion de la Operacion*/
	,'Moneda entregada' = 											(CUDP.Currencies_ShortName)
	,'Moneda recibida' = 											(CULP.Currencies_ShortName)
	,'Fecha de Inicio' = 											CONVERT(DATE,SWP.TradeDate)
	,'Fecha de Vencimiento' = 										CONVERT(DATE,SWL.MaturityDate)


/*Contraparte*/
	,'Nombre' = 													Cy.Cpty_Name
	,'Residente / No Residente' = 									(CASE 	WHEN Cy.IsResident = 'Y'
																			THEN 'R'
																			ELSE 'NR'
																			END)
	,'Pais' = 														(SELECT 	Ci.Cities_ShortName
																				FROM KplusLocal..Cities Ci WITH(NOLOCK)
																				WHERE Cy.Cities_Id = Ci.Cities_Id)
	,'Documento' = 													(CASE	WHEN CyPE.Documento IS NOT NULL
																			THEN CONVERT(VARCHAR,CyPE.Documento)
																			ELSE 'NOSCCATT'
																			END)
	,'Financiero / No Financiero' = 								ISNULL((CASE 	WHEN CyC.CptyClasses_ShortName = 'AFP'
																					THEN 'AFP'
																					WHEN CyC.CptyClasses_ShortName IN ('EMP_BANCAR','EMP_FINANC','SAB','OTRS_EMP_F','BCOS_EXTER','FONDOS_MUT','FONDOS_PUB','SOC_AG_BOL','EMP_ARR_FI')
																					THEN 'F'
																					ELSE 'NF'
																			END),'NF')
	,'Codigo SBS' = 												ISNULL(CyPE.CodigoSBS,0)
	,'Codigo de deudor' = 											 Cy.Cpty_ShortName
	,'Ponderacion por vencimiento residual (riesgo de credito)' = 	(CASE 	WHEN DATEDIFF(DAY,@FECHAEJECUCION,SWL.MaturityDate)>=0 AND DATEDIFF(DAY,@FECHAEJECUCION,SWL.MaturityDate)<=30
																			THEN 2.5
																			WHEN DATEDIFF(DAY,@FECHAEJECUCION,SWL.MaturityDate)>=31 AND DATEDIFF(DAY,@FECHAEJECUCION,SWL.MaturityDate)<=60
																			THEN 4
																			WHEN DATEDIFF(DAY,@FECHAEJECUCION,SWL.MaturityDate)>=61 AND DATEDIFF(DAY,@FECHAEJECUCION,SWL.MaturityDate)<=90
																			THEN 5.25
																			WHEN DATEDIFF(DAY,@FECHAEJECUCION,SWL.MaturityDate)>=91 AND DATEDIFF(DAY,@FECHAEJECUCION,SWL.MaturityDate)<=180
																			THEN 6.75
																			WHEN DATEDIFF(DAY,@FECHAEJECUCION,SWL.MaturityDate)>=181 AND DATEDIFF(DAY,@FECHAEJECUCION,SWL.MaturityDate)<=360
																			THEN 9.5
																			ELSE 12.25
																	END)/100
	,'Convenio marco de contratacion' = 							ISNULL( ( CASE	WHEN CyPE.CM_DRV = 'Y'
																					THEN 'S'
																					ELSE 'N'
																					END),'N')

/*Tipo de Cambio Spot*/
	,'Inicial' = 													(CASE	WHEN TY.TypeOfInstr_ShortName = 'SC'
																			THEN (CASE	WHEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY_MARKET_RISK(1, CUDP.Currencies_Id, CULP.Currencies_Id, SWP.TradeDate))<1
																						THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY_MARKET_RISK(1, CULP.Currencies_Id, CUDP.Currencies_Id, SWP.TradeDate))
																						ELSE (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY_MARKET_RISK(1, CUDP.Currencies_Id, CULP.Currencies_Id, SWP.TradeDate))
																				END)
																			ELSE (CASE 	WHEN SWP.FixingRate = 0
																						THEN 1
																						ELSE SWP.FixingRate
																				END)
																	END)
	,'Al cierre en la fecha de reporte' = 							(CASE	WHEN ((CULP.Currencies_ShortName = 'PEN') AND (CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))) OR ((CULP.Currencies_ShortName IN ('EUR','JPY','GBP')) AND (CUDP.Currencies_ShortName = 'USD'))
																			THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, CUDP.Currencies_Id, @PEN, @FECHAEJECUCION))
																			WHEN ((CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP')) AND (CUDP.Currencies_ShortName = 'PEN')) OR ((CULP.Currencies_ShortName = 'USD') AND (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP')))
																			THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, CULP.Currencies_Id, @PEN, @FECHAEJECUCION))
																	END)
	,'Tipo de Cambio Pactado' = 									(CASE	WHEN TY.TypeOfInstr_ShortName = 'SC'
																			THEN (CASE	WHEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY_MARKET_RISK(1, CUDP.Currencies_Id, CULP.Currencies_Id, SWP.TradeDate))<1
																						THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY_MARKET_RISK(1, CULP.Currencies_Id, CUDP.Currencies_Id, SWP.TradeDate))
																						ELSE (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY_MARKET_RISK(1, CUDP.Currencies_Id, CULP.Currencies_Id, SWP.TradeDate))
																				END)
																			ELSE (CASE 	WHEN SWP.FixingRate = 0
																						THEN 1
																						ELSE SWP.FixingRate
																				END)
																	END)
/*Valor de Mercado (Valor Actual)*/
	,'Por Tasa de Interes' = 									CONVERT(DECIMAL(18,2), (CASE 	WHEN (CULP.Currencies_ShortName = 'USD')
																											THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, CULP.Currencies_Id, @PEN, @DIAHABIL))
																											ELSE 1
																											END) * ISNULL( (SELECT 	MTM_L
																																		FROM	@TBL_PE_MTM_SWAP MTMSWP
																																		WHERE 	MTMSWP.SwapDeals_Id = SWL.SwapDeals_Id
																																		AND		DATEDIFF ( DAY, MTMSWP.Fecha_Reporte, @DIAHABIL) = 0),0))
																	+
																	CONVERT(DECIMAL(18,2), (CASE 	WHEN (CUDP.Currencies_ShortName = 'USD')
																											THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, CUDP.Currencies_Id, @PEN, @DIAHABIL))
																											ELSE 1
																											END) * ISNULL( (SELECT 	MTM_D
																																		FROM	@TBL_PE_MTM_SWAP MTMSWP
																																		WHERE 	MTMSWP.SwapDeals_Id = SWD.SwapDeals_Id
																																		AND		DATEDIFF ( DAY, MTMSWP.Fecha_Reporte, @DIAHABIL) = 0),0))
																-	(ISNULL((CASE	WHEN ((CULP.Currencies_ShortName = 'PEN') AND (CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))) OR ((CULP.Currencies_ShortName IN ('EUR','JPY','GBP')) AND (CUDP.Currencies_ShortName = 'USD'))
																					THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, CUDP.Currencies_Id, @PEN, @FECHAEJECUCION))
																					WHEN ((CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP')) AND (CUDP.Currencies_ShortName = 'PEN')) OR ((CULP.Currencies_ShortName = 'USD') AND (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP')))
																					THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, CULP.Currencies_Id, @PEN, @FECHAEJECUCION))
																			END)
																		- (CASE	WHEN TY.TypeOfInstr_ShortName = 'SC'
																			THEN (CASE	WHEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY_MARKET_RISK(1, CUDP.Currencies_Id, CULP.Currencies_Id, SWP.TradeDate))<1
																						THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY_MARKET_RISK(1, CULP.Currencies_Id, CUDP.Currencies_Id, SWP.TradeDate))
																						ELSE (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY_MARKET_RISK(1, CUDP.Currencies_Id, CULP.Currencies_Id, SWP.TradeDate))
																				END)
																			ELSE (CASE 	WHEN SWP.FixingRate = 0
																						THEN 1
																						ELSE SWP.FixingRate
																				END)
																	END),0)
																* 	(CASE	WHEN ((CULP.Currencies_ShortName = 'PEN') AND (CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))) OR ((CULP.Currencies_ShortName = 'USD') AND (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP')))
																			THEN -1
																			WHEN ((CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP')) AND (CUDP.Currencies_ShortName = 'PEN')) OR ((CULP.Currencies_ShortName IN ('EUR','JPY','GBP')) AND (CUDP.Currencies_ShortName = 'USD'))
																			THEN 1
																	END)
																* 	CONVERT(DECIMAL(18,2),ISNULL((CASE	WHEN ((CULP.Currencies_ShortName = 'PEN')
																										AND	 ((CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))))
																										OR	((CULP.Currencies_ShortName = 'USD')
																										AND	 (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP')))
																										THEN	(SELECT TOP 1 SWS.Principal
																													FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																													WHERE 	SWS.SwapDeals_Id = SWD.SwapDeals_Id
																													AND		SWS.ScheduleLeg = SWD.LegType
																													AND		SWS.CashFlowType = 'I'
																													AND		SWS.PeriodType = 'P'
																													AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																													ORDER BY SWS.EndDate ASC)
																										WHEN ((CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
																										AND	 (CUDP.Currencies_ShortName = 'PEN'))
																										OR	((CULP.Currencies_ShortName IN ('EUR','JPY','GBP'))
																										AND	 (CUDP.Currencies_ShortName = 'USD'))
																										THEN	(CASE 	WHEN TY.TypeOfInstr_ShortName = 'SC'
																														THEN SWL.PrincipalAmount
																														ELSE (SELECT TOP 1 SWS.Principal
																																FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																																AND		SWS.ScheduleLeg = SWL.LegType
																																AND		SWS.CashFlowType = 'I'
																																AND		SWS.PeriodType = 'P'
																																AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																													ORDER BY SWS.EndDate ASC)
																												END)
																								END),0)))
	,'Por Tipo de Cambio' =                                     ISNULL((CASE	WHEN ((CULP.Currencies_ShortName = 'PEN') AND (CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))) OR ((CULP.Currencies_ShortName IN ('EUR','JPY','GBP')) AND (CUDP.Currencies_ShortName = 'USD'))
																					THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, CUDP.Currencies_Id, @PEN, @FECHAEJECUCION))
																					WHEN ((CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP')) AND (CUDP.Currencies_ShortName = 'PEN')) OR ((CULP.Currencies_ShortName = 'USD') AND (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP')))
																					THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, CULP.Currencies_Id, @PEN, @FECHAEJECUCION))
																			END)
																		- (CASE	WHEN TY.TypeOfInstr_ShortName = 'SC'
																			THEN (CASE	WHEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY_MARKET_RISK(1, CUDP.Currencies_Id, CULP.Currencies_Id, SWP.TradeDate))<1
																						THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY_MARKET_RISK(1, CULP.Currencies_Id, CUDP.Currencies_Id, SWP.TradeDate))
																						ELSE (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY_MARKET_RISK(1, CUDP.Currencies_Id, CULP.Currencies_Id, SWP.TradeDate))
																				END)
																			ELSE (CASE 	WHEN SWP.FixingRate = 0
																						THEN 1
																						ELSE SWP.FixingRate
																				END)
																	END),0)
																* 	(CASE	WHEN ((CULP.Currencies_ShortName = 'PEN') AND (CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))) OR ((CULP.Currencies_ShortName = 'USD') AND (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP')))
																			THEN -1
																			WHEN ((CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP')) AND (CUDP.Currencies_ShortName = 'PEN')) OR ((CULP.Currencies_ShortName IN ('EUR','JPY','GBP')) AND (CUDP.Currencies_ShortName = 'USD'))
																			THEN 1
																	END)
																* 	CONVERT(DECIMAL(18,2),ISNULL((CASE	WHEN ((CULP.Currencies_ShortName = 'PEN')
																										AND	 ((CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))))
																										OR	((CULP.Currencies_ShortName = 'USD')
																										AND	 (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP')))
																										THEN	(SELECT TOP 1 SWS.Principal
																													FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																													WHERE 	SWS.SwapDeals_Id = SWD.SwapDeals_Id
																													AND		SWS.ScheduleLeg = SWD.LegType
																													AND		SWS.CashFlowType = 'I'
																													AND		SWS.PeriodType = 'P'
																													AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																													ORDER BY SWS.EndDate ASC)
																										WHEN ((CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
																										AND	 (CUDP.Currencies_ShortName = 'PEN'))
																										OR	((CULP.Currencies_ShortName IN ('EUR','JPY','GBP'))
																										AND	 (CUDP.Currencies_ShortName = 'USD'))
																										THEN	(CASE 	WHEN TY.TypeOfInstr_ShortName = 'SC'
																														THEN SWL.PrincipalAmount
																														ELSE (SELECT TOP 1 SWS.Principal
																																FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																																AND		SWS.ScheduleLeg = SWL.LegType
																																AND		SWS.CashFlowType = 'I'
																																AND		SWS.PeriodType = 'P'
																																AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																													ORDER BY SWS.EndDate ASC)
																												END)
																								END),0))
																--*	ISNULL((CONVERT(DECIMAL(17,6),(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1,Cu2.Currencies_Id, @PEN, @FECHAEJECUCION)))),0)
	,'Total' =                                                      CONVERT(DECIMAL(18,2), (CASE 	WHEN (CULP.Currencies_ShortName = 'USD')
																											THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, CULP.Currencies_Id, @PEN, @DIAHABIL))
																											ELSE 1
																											END) * ISNULL( (SELECT 	MTM_L
																																		FROM	@TBL_PE_MTM_SWAP MTMSWP
																																		WHERE 	MTMSWP.SwapDeals_Id = SWL.SwapDeals_Id
																																		AND		DATEDIFF ( DAY, MTMSWP.Fecha_Reporte, @DIAHABIL) = 0),0))
																	+
																	CONVERT(DECIMAL(18,2), (CASE 	WHEN (CUDP.Currencies_ShortName = 'USD')
																											THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, CUDP.Currencies_Id, @PEN, @DIAHABIL))
																											ELSE 1
																											END) * ISNULL( (SELECT 	MTM_D
																																		FROM	@TBL_PE_MTM_SWAP MTMSWP
																																		WHERE 	MTMSWP.SwapDeals_Id = SWD.SwapDeals_Id
																																		AND		DATEDIFF ( DAY, MTMSWP.Fecha_Reporte, @DIAHABIL) = 0),0))
	,'Intencion de Contratacion' = 									(CASE 	WHEN LEFT(F.Folders_ShortName,4) = 'TRAD'
																			THEN 'N'
																			WHEN LEFT(F.Folders_ShortName,3) = 'ALM'
																			THEN 'CC'
																	END)
/*Cobertura del Instrumento*/
	,'Partida Cubierta' = 											''--ISNULL(SWPCob.PARTIDA_CUBIERTA,'')
	,'Porcentaje de cobertura' =                                    '0'--ISNULL(SWPCob.PORCENTAJE_COBERTURA,0)
	,'Eficacia de Cobertura' =                                      '0'--ISNULL(SWPCob.EFICACIA_COBERTURA,0)

	,'Forma de Pago' = 												(CASE	WHEN (Kustom.dbo.FUNC_DRV_SWAP_Delivery_Mode(SWP.SwapDeals_Id)) = 'D'
																			THEN 'Delivery'
																			ELSE 'Sin Delivery'
																	END)

/*Tasas Anuales de Interes Utilizadas al Fijar Precio*/
	,'Moneda Entregada' = 											ISNULL(CONVERT(DECIMAL(18,4),(CASE 	WHEN SWD.Indexation = 'F'
																										THEN SWD.FixedRate
																										ELSE (SELECT FRV.Rate
																												FROM	KplusLocal..FloatingRatesValues FRV WITH(NOLOCK)
																												WHERE 	SWD.FloatingRates_Id = FRV.FloatingRates_Id
																												AND		DATEDIFF(DAY,FRV.FRDate,SWP.TradeDate) = 0) +
																											(SWD.AdditiveMargin/100)
																	END)),0)/100
	,'Moneda Recibida' = 												ISNULL(CONVERT(DECIMAL(18,4),(CASE 	WHEN SWL.Indexation = 'F'
																										THEN SWL.FixedRate
																										ELSE (SELECT FRV.Rate
																												FROM	KplusLocal..FloatingRatesValues FRV WITH(NOLOCK)
																												WHERE 	SWL.FloatingRates_Id = FRV.FloatingRates_Id
																												AND		DATEDIFF(DAY,FRV.FRDate,SWP.TradeDate) = 0)  +
																											(SWL.AdditiveMargin/100)
																	END)),0)/100
/*Tasas Anuales de Interes Spot en la fecha de reporte*/
	,'Moneda Entregada' = 											ISNULL(CONVERT(DECIMAL(18,4),(CASE 	WHEN SWD.Indexation = 'F'
																										THEN SWD.FixedRate
																										ELSE (SELECT FRV.Rate
																												FROM	KplusLocal..FloatingRatesValues FRV WITH(NOLOCK)
																												WHERE 	SWD.FloatingRates_Id = FRV.FloatingRates_Id
																												AND		DATEDIFF(DAY,FRV.FRDate,@FECHAEJECUCION) = 0)  +
																											(SWD.AdditiveMargin/100)

																	END)),0)/100
	,'Moneda Recibida' = 											ISNULL(CONVERT(DECIMAL(18,4),(CASE 	WHEN SWL.Indexation = 'F'
																										THEN SWL.FixedRate
																										ELSE (SELECT FRV.Rate
																												FROM	KplusLocal..FloatingRatesValues FRV WITH(NOLOCK)
																												WHERE 	SWL.FloatingRates_Id = FRV.FloatingRates_Id
																												AND		DATEDIFF(DAY,FRV.FRDate,@FECHAEJECUCION) = 0)  +
																											(SWL.AdditiveMargin/100)
																	END)),0)/100
	,' ' =															''
	,'Codigo BT' = 													Cy.Cpty_ShortName
	,'Codigo Cartera' = 											(CASE 	WHEN LEFT(SWP.DownloadKey,1) <> '#'
																			THEN RIGHT(SWP.DownloadKey,5)
																			ELSE CONVERT(VARCHAR,SWP.SwapDeals_Id)
																	END)
FROM 		KplusLocal..SwapDeals SWP WITH(NOLOCK)
INNER JOIN	@RTK_SWP_DEALS RTKSWP
	ON		SWP.SwapDeals_Id = RTKSWP.SwapDeals_Id
INNER JOIN 	KplusLocal..SwapLeg SWL WITH(NOLOCK)
	ON 			SWP.SwapDeals_Id = SWL.SwapDeals_Id
	AND 		SWL.LegType = 'L'
INNER JOIN 	KplusLocal..SwapLeg SWD WITH(NOLOCK)
	ON 			SWP.SwapDeals_Id = SWD.SwapDeals_Id
	AND 		SWD.LegType  = 'D'
INNER JOIN	KplusLocal..Currencies CUL WITH(NOLOCK)
	ON 			CUL.Currencies_Id = SWL.Currencies_Id
INNER JOIN	KplusLocal..Currencies CUD WITH(NOLOCK)
	ON 			CUD.Currencies_Id = SWD.Currencies_Id
INNER JOIN	KplusLocal..Currencies CULP WITH(NOLOCK)
	ON 			CULP.Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))
INNER JOIN	KplusLocal..Currencies CUDP WITH(NOLOCK)
	ON 			CUDP.Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))
INNER JOIN	KplusLocal..Folders F WITH(NOLOCK)
	ON 			F.Folders_Id = SWL.Folders_Id
INNER JOIN  Kustom..TBL_REG_SCOTIAZONE_HIERARCHY	TBL_H WITH(NOLOCK)
	ON 			SWL.Folders_Id = TBL_H.Folders_Id
	AND 		TBL_H.Regions_Id = @Regions_Id
INNER JOIN	KplusLocal..TypeOfInstr TY WITH(NOLOCK)
	ON 			SWL.TypeOfInstr_Id = TY.TypeOfInstr_Id
INNER JOIN	KplusLocal..Cpty Cy WITH(NOLOCK)
	ON 			Cy.Cpty_Id = SWL.Cpty_Id
	AND 		TY.TypeOfInstr_ShortName IN ('CCS','SC')
	AND			SWP.DealStatus		IN ('V')
	AND 		SWP.InputMode		NOT IN	('G')
	AND 		SWP.TypeOfEvent		NOT IN 	('M')
	AND			DATEDIFF(DAY,SWP.TradeDate,@FECHAEJECUCION) >= 0
	AND			DATEDIFF(DAY,ISNULL(SWP.LiquidationDate,SWL.MaturityDate),@FECHAEJECUCION)     < 0

		--AND			SWP.SwapDeals_Id NOT IN (26986,27018,27025,27028,27020,27021,27029,27033,27034)
--LEFT JOIN	Kustom..TBL_PE_DRV_SWP_COBERTURA SWPCob
--	ON			SWPCob.DealId = SWP.SwapDeals_Id
--	AND 		SWPCob.DealType = 'SwapDeals'
LEFT JOIN	Kustom.dbo.TBL_PE_CPTY_CUSTOM	CyPE WITH(NOLOCK)
	ON 			Cy.Cpty_Id = CyPE.DealId
LEFT JOIN	KplusLocal..CptyClasses CyC WITH(NOLOCK)
	ON			CyC.CptyClasses_Id = Cy.CptyClasses_Id
	order by 2 ASC

		SELECT __TITLE__ = 'Operaciones a Futuro con ME'
		SELECT __ELEM_TITLE__ = 'ANEXO8ASWPME'+CONVERT(VARCHAR(8),@FECHAEJECUCION,112)

SElECT * FROM @DRVME order by 4 asc


	--LM_KONDORG_14011: Inicio
	--------------------------------------------------------------------
	-- A N E X O (A) : F X O P T I O N S  M. E.  
	--------------------------------------------------------------------
	IF OBJECT_ID('tempdb..#FxOpt_AnexoA') IS NOT NULL
	BEGIN
		DROP TABLE #FxOpt_AnexoA;
	END
	
	--Obtener operaciones FXO
	CREATE TABLE #FxOpt_AnexoA(
	 [FxOptionsDeals_Id] 										INT
	,[TradeDate] 												DATE
	,[PremiumPayment] 											CHAR(1)
	,[Pairs_Id]													INT
	,[MarketValue]												FLOAT
	,[Cuenta Contable]											VARCHAR(13)
	,[Por Cada Contrato u Operacion Vigente]					VARCHAR(23)
	,[Codigo de la operacion]									VARCHAR(35)
	,[Saldo Contable]											DECIMAL(18,2)
	,[Moneda pactada]											VARCHAR(3)
	,[Monto Nominal Pactado]									DECIMAL(18,2)
	,[Moneda entregada]											VARCHAR(3)
	,[Moneda recibida]											VARCHAR(3)
	,[Tipo de Opcion]											VARCHAR(8)
	,[Fecha de Inicio]											DATE
	,[Fecha de Vencimiento]										DATE
	,[Nombre]													VARCHAR(32)
	,[Residente / No Residente]									VARCHAR(2)
	,[Pais]														VARCHAR(10)
	,[Documento]												VARCHAR(30)
	,[Financiero / No Financiero]								VARCHAR(3)
	,[Codigo SBS]												VARCHAR(19)
	,[Codigo de deudor]											VARCHAR(10)
	,[Ponderacion por vencimiento residual (riesgo de credito)]	NUMERIC(5,4)
	,[Convenio marco de contratacion]							CHAR(1)
	,[Inicial]													FLOAT
	,[Al cierre en la fecha de reporte]							FLOAT
	,[Volatilidad del tipo de cambio ]							DECIMAL(8,4)
	,[Tipo de Cambio Pactado]									DECIMAL(8,4)
	,[Prima Pagada]												DECIMAL(20,2)
	,[Delta]													DECIMAL(8,4)
	,[Gamma]													DECIMAL(8,4)
	,[Vega ]													DECIMAL(8,4)
	,[Intencion de Contratacion]								VARCHAR(2)
	,[Partida Cubierta]											CHAR(1)
	,[Porcentaje de cobertura]									CHAR(1)
	,[Eficacia de Cobertura]									CHAR(1)
	,[Tasa de Interes al fijar precio Entregada]				FLOAT
	,[Tasa de Interes al fijar precio Recibida]	 				FLOAT
	,[Tasa de Interes a la fecha del reporte Entregada]			FLOAT
	,[Tasa de Interes a la fecha del reporte  Recibida]			FLOAT
	,[Con delivery/ Sin delivery]								VARCHAR(12)
	,[Descripcion]												CHAR(1)
	,[Precio Valor Actual]										FLOAT 
	);
	
	CREATE INDEX FxOpt_AnexoA_FxOptionsDeals_Id1	ON #FxOpt_AnexoA (FxOptionsDeals_Id);
	
	INSERT INTO #FxOpt_AnexoA (
	 [FxOptionsDeals_Id]
	,[TradeDate]
	,[PremiumPayment]
	,[Pairs_Id]
	,[MarketValue]
	,[Cuenta Contable]
	,[Por Cada Contrato u Operacion Vigente]
	,[Codigo de la operacion]
	,[Saldo Contable]
	,[Moneda pactada]
	,[Monto Nominal Pactado]
	,[Moneda entregada]
	,[Moneda recibida]
	,[Tipo de Opcion]
	,[Fecha de Inicio]
	,[Fecha de Vencimiento]
	,[Nombre]
	,[Residente / No Residente]
	,[Pais]
	,[Documento]
	,[Financiero / No Financiero]
	,[Codigo SBS]
	,[Codigo de deudor]
	,[Ponderacion por vencimiento residual (riesgo de credito)]
	,[Convenio marco de contratacion]
	,[Inicial]
	,[Al cierre en la fecha de reporte]
	,[Volatilidad del tipo de cambio ]
	,[Tipo de Cambio Pactado]
	,[Prima Pagada]
	,[Delta]
	,[Gamma]
	,[Vega ]
	,[Intencion de Contratacion]
	,[Partida Cubierta]
	,[Porcentaje de cobertura]
	,[Eficacia de Cobertura]
	,[Tasa de Interes al fijar precio Entregada]
	,[Tasa de Interes al fijar precio Recibida]
	,[Tasa de Interes a la fecha del reporte Entregada]
	,[Tasa de Interes a la fecha del reporte  Recibida]
	,[Con delivery/ Sin delivery]
	,[Descripcion]
	,[Precio Valor Actual]
	)
	SELECT
 RTK.FxOptionsDeals_FxOptionsDeals_Id
,TRY_CONVERT(DATE, RTK.ValuationData_TradeDate, 103) AS TradeDate
,CASE 
	WHEN RTK.FxOptionsDeals_PremiumPayment = 'Currency 1' THEN '1'
	WHEN RTK.FxOptionsDeals_PremiumPayment = 'Currency 2' THEN '2'
	ELSE '1'
 END AS PremiumPayment
,Pair.Pairs_Id
,RTK.ValuationData_MarketValue
,'Cuenta Contable' = 												(CASE	WHEN RTK.ValuationData_BuyOrSell = 'Buy' AND RTK.ValuationData_CallPut = 'Call'
																			THEN '7106.01.05.01'
																			WHEN RTK.ValuationData_BuyOrSell = 'Buy' AND RTK.ValuationData_CallPut = 'Put'
																			THEN '7106.01.05.03'
																			WHEN RTK.ValuationData_BuyOrSell = 'Sell' AND RTK.ValuationData_CallPut = 'Call'
																			THEN '7206.01.05.02'
																			WHEN RTK.ValuationData_BuyOrSell = 'Sell' AND RTK.ValuationData_CallPut = 'Put'
																			THEN '7206.01.05.04'
																	END)
,'Por Cada Contrato u Operacion Vigente' = 							(CASE	WHEN RTK.ValuationData_BuyOrSell = 'Buy' AND RTK.ValuationData_CallPut = 'Call'
																			THEN 'Compra de Opciones Call'
																			WHEN RTK.ValuationData_BuyOrSell = 'Buy' AND RTK.ValuationData_CallPut = 'Put'
																			THEN 'Compra de Opciones Put'
																			WHEN RTK.ValuationData_BuyOrSell = 'Sell' AND RTK.ValuationData_CallPut = 'Call'
																			THEN 'Venta de Opciones Call'
																			WHEN RTK.ValuationData_BuyOrSell = 'Sell' AND RTK.ValuationData_CallPut = 'Put'
																			THEN 'Venta de Opciones Put'
																	END)
,'Codigo de la operacion' = 										(CASE	WHEN RTK.ValuationData_BuyOrSell = 'Buy' AND RTK.ValuationData_CallPut = 'Call'
																			THEN 'OPTCC'
																			WHEN RTK.ValuationData_BuyOrSell = 'Buy' AND RTK.ValuationData_CallPut = 'Put'
																			THEN 'OPTPC'
																			WHEN RTK.ValuationData_BuyOrSell = 'Sell' AND RTK.ValuationData_CallPut = 'Call'
																			THEN 'OPTCV'
																			WHEN RTK.ValuationData_BuyOrSell = 'Sell' AND RTK.ValuationData_CallPut = 'Put'
																			THEN 'OPTPV'
																	END) + CONVERT(VARCHAR,RTK.FxOptionsDeals_FxOptionsDeals_Id)
,'Saldo Contable' = 												CONVERT(DECIMAL(18,2),(CASE	WHEN C1.Currencies_ShortName = 'PEN'
																								THEN RTK.FxOptionsDeals_NotionalAmount2 * (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, C2.Currencies_Id, C1.Currencies_Id, @FECHAEJECUCION))
																								WHEN C2.Currencies_ShortName = 'PEN'
																								THEN RTK.FxOptionsDeals_NotionalAmount1 * (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, C1.Currencies_Id, C2.Currencies_Id, @FECHAEJECUCION))
																								WHEN C1.Currencies_ShortName <> 'PEN' AND C2.Currencies_ShortName <> 'PEN'
																								THEN RTK.FxOptionsDeals_NotionalAmount1 * (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, C1.Currencies_Id, C2.Currencies_Id, @FECHAEJECUCION))
																						END))
,'Moneda pactada' = 												(CASE	-- VP_KONDORG_14011_202511:Inicio
																			-- Regla 1: Si el par contiene PEN, la moneda pactada es la otra
																			WHEN C1.Currencies_ShortName = 'PEN'
																			THEN C2.Currencies_ShortName
																			
																			WHEN C2.Currencies_ShortName = 'PEN'
																			THEN C1.Currencies_ShortName
																			
																			-- Regla 2: Si el par contiene USD (pero NO PEN), la moneda pactada es la otra
																			WHEN C1.Currencies_ShortName = 'USD'
																			THEN C2.Currencies_ShortName
																			
																			WHEN C2.Currencies_ShortName = 'USD'
																			THEN C1.Currencies_ShortName
																			
																			-- Regla 3: Si NO tiene PEN ni USD, usar logica original
																			ELSE (CASE	WHEN C1.Currencies_ShortName IN ('JPY','GBP','EUR','CAD')
																						THEN C1.Currencies_ShortName
																						ELSE C2.Currencies_ShortName
																				END)
																	END) -- VP_KONDORG_14011_202511:Fin
,'Monto Nominal Pactado' = 											CONVERT(DECIMAL(18,2),(CASE	WHEN C1.Currencies_ShortName = 'PEN'
																								THEN RTK.FxOptionsDeals_NotionalAmount2
																								WHEN C2.Currencies_ShortName = 'PEN'
																								THEN RTK.FxOptionsDeals_NotionalAmount1
																								WHEN C1.Currencies_ShortName <> 'PEN' AND C2.Currencies_ShortName <> 'PEN'
																								THEN (CASE	WHEN C1.Currencies_ShortName IN ('JPY','GBP','EUR')
																											THEN RTK.FxOptionsDeals_NotionalAmount1
																											ELSE RTK.FxOptionsDeals_NotionalAmount2
																									END)
																						END))

/*Descripcion de la Operacion*/
,'Moneda entregada' = 												(CASE	-- VP_KONDORG_14011_202511:Inicio
																			-- Logica basada en Buy/Sell y Call/Put con Moneda Pactada
																			WHEN (RTK.ValuationData_BuyOrSell = 'Sell' AND RTK.ValuationData_CallPut = 'Call') 
																			  OR (RTK.ValuationData_BuyOrSell = 'Buy' AND RTK.ValuationData_CallPut = 'Put')
																			THEN 
																				-- Retornar Moneda Pactada (aplicando la nueva logica)
																				(CASE	
																					WHEN C1.Currencies_ShortName = 'PEN' THEN C2.Currencies_ShortName
																					WHEN C2.Currencies_ShortName = 'PEN' THEN C1.Currencies_ShortName
																					WHEN C1.Currencies_ShortName = 'USD' THEN C2.Currencies_ShortName
																					WHEN C2.Currencies_ShortName = 'USD' THEN C1.Currencies_ShortName
																					ELSE (CASE	WHEN C1.Currencies_ShortName IN ('JPY','GBP','EUR','CAD')
																								THEN C1.Currencies_ShortName
																								ELSE C2.Currencies_ShortName
																						END)
																				END)
																			ELSE 
																				-- Retornar la Otra Moneda (la que NO es pactada)
																				(CASE	
																					WHEN C1.Currencies_ShortName = 'PEN' THEN C1.Currencies_ShortName
																					WHEN C2.Currencies_ShortName = 'PEN' THEN C2.Currencies_ShortName
																					WHEN C1.Currencies_ShortName = 'USD' THEN C1.Currencies_ShortName
																					WHEN C2.Currencies_ShortName = 'USD' THEN C2.Currencies_ShortName
																					ELSE (CASE	WHEN C1.Currencies_ShortName IN ('JPY','GBP','EUR','CAD')
																								THEN C2.Currencies_ShortName
																								ELSE C1.Currencies_ShortName
																						END)
																				END)
																	END)
,'Moneda recibida' = 												(CASE	
																			-- Logica basada en Buy/Sell y Call/Put con Moneda Pactada
																			WHEN (RTK.ValuationData_BuyOrSell = 'Buy' AND RTK.ValuationData_CallPut = 'Call') 
																			  OR (RTK.ValuationData_BuyOrSell = 'Sell' AND RTK.ValuationData_CallPut = 'Put')
																			THEN 
																				-- Retornar Moneda Pactada (aplicando la nueva logica)
																				(CASE	
																					WHEN C1.Currencies_ShortName = 'PEN' THEN C2.Currencies_ShortName
																					WHEN C2.Currencies_ShortName = 'PEN' THEN C1.Currencies_ShortName
																					WHEN C1.Currencies_ShortName = 'USD' THEN C2.Currencies_ShortName
																					WHEN C2.Currencies_ShortName = 'USD' THEN C1.Currencies_ShortName
																					ELSE (CASE	WHEN C1.Currencies_ShortName IN ('JPY','GBP','EUR','CAD')
																								THEN C1.Currencies_ShortName
																								ELSE C2.Currencies_ShortName
																						END)
																				END)
																			ELSE 
																				-- Retornar la Otra Moneda (la que NO es pactada)
																				(CASE	
																					WHEN C1.Currencies_ShortName = 'PEN' THEN C1.Currencies_ShortName
																					WHEN C2.Currencies_ShortName = 'PEN' THEN C2.Currencies_ShortName
																					WHEN C1.Currencies_ShortName = 'USD' THEN C1.Currencies_ShortName
																					WHEN C2.Currencies_ShortName = 'USD' THEN C2.Currencies_ShortName
																					ELSE (CASE	WHEN C1.Currencies_ShortName IN ('JPY','GBP','EUR','CAD')
																								THEN C2.Currencies_ShortName
																								ELSE C1.Currencies_ShortName
																						END)
																				END)
																	END) -- -- VP_KONDORG_14011_202511:Fin
,'Tipo de Opcion' = 												RTK.ValuationData_ExerciseType
,'Fecha de Inicio' = 												TRY_CONVERT(DATE, RTK.ValuationData_TradeDate, 103)
,'Fecha de Vencimiento' = 											TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103)
,'Nombre' = 													RTK.ValuationData_CptyName
,'Residente / No Residente' = 									(CASE 	WHEN Cy.IsResident = 'Y'
																		THEN 'R'
																		ELSE 'NR'
																		END)
,'Pais' = 														ISNULL(Ci.Cities_ShortName,'PE')
,'Documento' = 													(CASE	WHEN CyPE.Documento IS NOT NULL
																		THEN CONVERT(VARCHAR,CyPE.Documento)
																		ELSE 'NOSCCATT'
																		END)
,'Financiero / No Financiero' = 								ISNULL((CASE 	WHEN CyC.CptyClasses_ShortName = 'AFP'
																				THEN 'AFP'
																				WHEN CyC.CptyClasses_ShortName IN ('EMP_BANCAR','EMP_FINANC','SAB','OTRS_EMP_F','BCOS_EXTER','FONDOS_MUT','FONDOS_PUB','SOC_AG_BOL','EMP_ARR_FI')
																				THEN 'F'
																				ELSE 'NF'
																		END),'NF')
,'Codigo SBS' = 												ISNULL(CyPE.CodigoSBS,0)
,'Codigo de deudor' = 											RTK.ValuationData_CptyShortName
,'Ponderacion por vencimiento residual (riesgo de credito)' = 	(CASE 	WHEN DATEDIFF(DAY,@FECHAEJECUCION,TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103))>=0 AND DATEDIFF(DAY,@FECHAEJECUCION,TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103))<=30
																		THEN 2.5
																		WHEN DATEDIFF(DAY,@FECHAEJECUCION,TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103))>=31 AND DATEDIFF(DAY,@FECHAEJECUCION,TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103))<=60
																		THEN 4
																		WHEN DATEDIFF(DAY,@FECHAEJECUCION,TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103))>=61 AND DATEDIFF(DAY,@FECHAEJECUCION,TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103))<=90
																		THEN 5.25
																		WHEN DATEDIFF(DAY,@FECHAEJECUCION,TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103))>=91 AND DATEDIFF(DAY,@FECHAEJECUCION,TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103))<=180
																		THEN 6.75
																		WHEN DATEDIFF(DAY,@FECHAEJECUCION,TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103))>=181 AND DATEDIFF(DAY,@FECHAEJECUCION,TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103))<=360
																		THEN 9.5
																		ELSE 12.25
																END)/100
,'Convenio marco de contratacion' = 							ISNULL(( CASE	WHEN CyPE.CM_DRV = 'Y'
																				THEN 'S'
																				ELSE 'N'
																				END),'N')

/*Tipo de Cambio Spot*/
,'Inicial' = 															(CASE	WHEN C1.Currencies_ShortName = 'PEN'
																				THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, C2.Currencies_Id, C1.Currencies_Id, TRY_CONVERT(DATE, RTK.ValuationData_TradeDate, 103)))
																				WHEN C2.Currencies_ShortName = 'PEN'
																				THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, C1.Currencies_Id, C2.Currencies_Id, TRY_CONVERT(DATE, RTK.ValuationData_TradeDate, 103)))
																				WHEN C1.Currencies_ShortName <> 'PEN' AND C2.Currencies_ShortName <> 'PEN'
																				THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, C1.Currencies_Id, C2.Currencies_Id, TRY_CONVERT(DATE, RTK.ValuationData_TradeDate, 103)))
																		END)
,'Al cierre en la fecha de reporte' = 									(CASE	WHEN C1.Currencies_ShortName = 'PEN'
																				THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, C2.Currencies_Id, C1.Currencies_Id, @FECHAEJECUCION))
																				WHEN C2.Currencies_ShortName = 'PEN'
																				THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, C1.Currencies_Id, C2.Currencies_Id, @FECHAEJECUCION))
																				WHEN C1.Currencies_ShortName <> 'PEN' AND C2.Currencies_ShortName <> 'PEN'
																				THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, C1.Currencies_Id, C2.Currencies_Id, @FECHAEJECUCION))
																		END)
/*
,'Volatilidad del tipo de cambio' = 									ISNULL(CONVERT(DECIMAL(8,4),(SELECT RTKFXO. ValuationData_Vola
																								FROM DataKondorPE..TBL_PE_RTK_FX_HIST RTKFXO WITH(NOLOCK)
																								WHERE FXO.FxOptionsDeals_Id = RTKFXO.FxOptionsDeals_FxOptionsDeals_Id
																								AND DATEDIFF(DAY,RTKFXO.Fecha,@FECHAEJECUCION) = 0)),0)
*/
,'Volatilidad del tipo de cambio ' =									ISNULL(CONVERT(DECIMAL(8,4),RTK.ValuationData_Vola),0)

,'Tipo de Cambio Pactado' = 											CONVERT(DECIMAL(8,4),RTK.Data_Spot)
,'Prima Pagada' = 														CONVERT(DECIMAL(18,2),(CASE	WHEN C1.Currencies_ShortName = 'PEN'
																									THEN RTK.FxOptionsDeals_PremiumAmount1
																									WHEN C2.Currencies_ShortName = 'PEN'
																									THEN RTK.FxOptionsDeals_PremiumAmount2
																									WHEN C1.Currencies_ShortName <> 'PEN' AND C2.Currencies_ShortName <> 'PEN'
																									THEN (CASE	WHEN C1.Currencies_ShortName IN ('JPY','GBP','EUR')
																												THEN RTK.FxOptionsDeals_PremiumAmount1*(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, C2.Currencies_Id, C1.Currencies_Id, @FECHAEJECUCION))
																												ELSE RTK.FxOptionsDeals_PremiumAmount2*(SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, C1.Currencies_Id, C2.Currencies_Id, @FECHAEJECUCION))
																										END)
																							END))
/*
,'Delta' = 																ISNULL(CONVERT(DECIMAL(8,4),(SELECT RTKFXO. ValuationData_Delta
																								FROM DataKondorPE..TBL_PE_RTK_FX_HIST RTKFXO WITH(NOLOCK)
																								WHERE FXO.FxOptionsDeals_Id = RTKFXO.FxOptionsDeals_FxOptionsDeals_Id
																								AND DATEDIFF(DAY,RTKFXO.Fecha,@FECHAEJECUCION) = 0)),0)


,'Gamma' = 																ISNULL(CONVERT(DECIMAL(8,4),(SELECT RTKFXO. ValuationData_Gamma
																								FROM DataKondorPE..TBL_PE_RTK_FX_HIST RTKFXO WITH(NOLOCK)
																								WHERE FXO.FxOptionsDeals_Id = RTKFXO.FxOptionsDeals_FxOptionsDeals_Id
																								AND DATEDIFF(DAY,RTKFXO.Fecha,@FECHAEJECUCION) = 0)),0)

,'Vega' = 																ISNULL(CONVERT(DECIMAL(8,4),(SELECT RTKFXO. ValuationData_Vega
																								FROM DataKondorPE..TBL_PE_RTK_FX_HIST RTKFXO WITH(NOLOCK)
																								WHERE FXO.FxOptionsDeals_Id = RTKFXO.FxOptionsDeals_FxOptionsDeals_Id
																								AND DATEDIFF(DAY,RTKFXO.Fecha,@FECHAEJECUCION) = 0)),0)
*/

,'Delta'																= ISNULL(CONVERT(DECIMAL(8,4),RTK.ValuationData_Delta),0) 

--LM_KONDORG_14011_202510:Inicio
/*
,'Gamma'																= ISNULL(CONVERT(DECIMAL(8,4),RTK.ValuationData_Gamma),0)  
,'Vega '																= ISNULL(CONVERT(DECIMAL(8,4),RTK.ValuationData_Vega),0)
*/

,'Gamma'																= ISNULL(CONVERT(DECIMAL(8,4),(RTK.ValuationData_Gamma * 100)/COALESCE(NULLIF(TC.Tipo_Cambio,0),1)),0)
,'Vega '																= ISNULL(CONVERT(DECIMAL(8,4),(RTK.ValuationData_Vega * 100)),0)

--LM_KONDORG_14011_202510:Fin

,'Intencion de Contratacion' = 											(CASE 	WHEN LEFT(RTK.StaticData_FoldersShortName,4) = 'TRAD'
																				THEN 'N'
																				WHEN LEFT(RTK.StaticData_FoldersShortName,3) = 'ALM'
																				THEN 'CC'
																		END)
/*Cobertura del Instrumento*/
,'Partida Cubierta' = 													''--ISNULL(FXOCob.PARTIDA_CUBIERTA,'')
,'Porcentaje de cobertura' =                                            ''--ISNULL(FXOCob.PORCENTAJE_COBERTURA,0)
,'Eficacia de Cobertura' =                                              ''--ISNULL(FXOCob.EFICACIA_COBERTURA,0)

/*Tasas de interes al fijar precio*/

,'Tasa de Interes al fijar precio Entregada' 							= NULL

,'Tasa de Interes al fijar precio Recibida' 							= NULL

/*Tasas de interes a la fecha del reporte*/

,'Tasa de Interes a la fecha del reporte Entregada' 					= 	(CASE	WHEN RTK.FxOptionsDeals_PremiumPayment = 'Currency 2'
																					THEN ISNULL(RTK.Data_RateCur2,0)
																					ELSE ISNULL(RTK.Data_RateCur1,0)
																			END)
,'Tasa de Interes a la fecha del reporte  Recibida' 					= 	(CASE	WHEN RTK.FxOptionsDeals_PremiumPayment = 'Currency 2'
																					THEN ISNULL(RTK.Data_RateCur1,0)
																					ELSE ISNULL(RTK.Data_RateCur2,0)
																			END)


/*Forma de Pago*/
,'Con delivery/ Sin delivery' = 										(CASE	WHEN RTK.FxOptionsDeals_SettlementMode LIKE '%Delivery%'
																				THEN 'Delivery'
																				ELSE 'Sin Delivery'
																		END)
,'Descripcion' = 														''
,[Precio Valor Actual] = NULL
	 
-- VP_KONDORG_14011_202511:Inicio - RTK es ahora la tabla principal
FROM	 	DataKondorPE..TBL_PE_RTK_FX_HIST RTK WITH(NOLOCK)
INNER JOIN	KplusLocal..Pairs 						Pair WITH(NOLOCK)
	ON		RTK.Pairs_Pairs_ShortName = Pair.Pairs_ShortName
LEFT JOIN	KplusLocal..Cpty 						Cy WITH(NOLOCK)
	ON 		RTK.ValuationData_CptyShortName = Cy.Cpty_ShortName

LEFT JOIN	KplusLocal..Cities						Ci WITH(NOLOCK)
	ON		Cy.Cities_Id = Ci.Cities_Id
LEFT JOIN	Kustom.dbo.TBL_PE_CPTY_CUSTOM	CyPE WITH(NOLOCK)
	ON 		Cy.Cpty_Id = CyPE.DealId
LEFT JOIN	KplusLocal..CptyClasses CyC WITH(NOLOCK)
	ON		CyC.CptyClasses_Id = Cy.CptyClasses_Id
LEFT JOIN	KplusLocal..CurrenciesDef 				C1 WITH(NOLOCK)
	ON		C1.Currencies_Id = Pair.Currencies_Id_1
LEFT JOIN	KplusLocal..CurrenciesDef 				C2 WITH(NOLOCK)
	ON		C2.Currencies_Id = Pair.Currencies_Id_2
-- VP_KONDORG_14011_202511:Fin

--LM_KONDORG_14011_202510:Inicio
-----------------------------------------------
-- Tipo_Cambio
-----------------------------------------------
LEFT JOIN @Pairs_TC TC 
ON TC.Pair_ShortName = Pair.Pairs_ShortName

--LM_KONDORG_14011_202510:Fin

WHERE		RTK.Fecha = @FECHAEJECUCION
AND			TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103) > @FECHAEJECUCION

	
	-----------------------------------------------
	--Calcular Tasas al fijar precio
	-----------------------------------------------
	DECLARE @DealsfxoMEtoSearch TABLE(
	FxOptionsDeals_Id INT  INDEX IX1 CLUSTERED NULL
	,TradeDate 		   DATE INDEX IX2 NONCLUSTERED NULL
	);
	INSERT INTO @DealsfxoMEtoSearch(
	FxOptionsDeals_Id
	,TradeDate
	)
	SELECT 
	FxOptionsDeals_Id
	,TradeDate
	FROM #FxOpt_AnexoA
	GROUP BY FxOptionsDeals_Id
			,TradeDate;
	
	DECLARE @DealsfxoMEFirstRateCur1_Cur2 TABLE(
	FxOptionsDeals_Id INT 
	,RateCur1 FLOAT,
	RateCur2 FLOAT
	);
	INSERT INTO  @DealsfxoMEFirstRateCur1_Cur2 (
	FxOptionsDeals_Id,RateCur1,RateCur2
	)
	SELECT 
		T.FxOptionsDeals_Id
		,ISNULL(FirstRateCur.Data_RateCur1,0)
		,ISNULL(FirstRateCur.Data_RateCur2,0) 
	FROM @DealsfxoMEtoSearch T
	OUTER APPLY(
				SELECT TOP 1 Data_RateCur1, Data_RateCur2
				FROM  DataKondorPE..TBL_PE_RTK_FX_HIST  RTK WITH(NOLOCK)
				WHERE   RTK.Fecha < =@FECHAEJECUCION
					AND RTK.Fecha = T.TradeDate
					AND RTK.FxOptionsDeals_FxOptionsDeals_Id = T.FxOptionsDeals_Id
				ORDER BY RTK.Fecha ASC	
	)FirstRateCur
	
	UPDATE T
	SET
	[Tasa de Interes al fijar precio Entregada] =
													(CASE	WHEN T.PremiumPayment = '2'
															THEN ISNULL(V.RateCur2,0)
															ELSE ISNULL(V.RateCur1,0)
													END)
	,[Tasa de Interes al fijar precio Recibida] =
													(CASE	WHEN T.PremiumPayment = '2'
															THEN ISNULL(V.RateCur1,0)
															ELSE ISNULL(V.RateCur2,0)
													END)
	
	FROM #FxOpt_AnexoA T
	LEFT JOIN @DealsfxoMEFirstRateCur1_Cur2 V
		ON T.FxOptionsDeals_Id = V.FxOptionsDeals_Id 
	
	-----------------------------------------------
	--Calcular Precio valor actual
	-----------------------------------------------
	
	DECLARE @CURRENCIES_A TABLE (Currencies_Id INT PRIMARY KEY)
	
	INSERT INTO @CURRENCIES_A (Currencies_Id)
	SELECT DISTINCT U.Currencies_Id
	FROM (
		SELECT P.Currencies_Id_1, P.Currencies_Id_2
		FROM KplusLocal..Pairs P WITH(NOLOCK)
		INNER JOIN #FxOpt_AnexoA F 
		ON F.Pairs_Id = P.Pairs_Id
	) AS AUX
	UNPIVOT (
		Currencies_Id FOR CurrencyCol IN (Currencies_Id_1, Currencies_Id_2)
	) AS U
	
	DECLARE @EXCHANGE_RATES_TO_PEN_FXO_A TABLE (
		Cur_Id INT PRIMARY KEY,
		TC     FLOAT NULL
	)
	INSERT INTO @EXCHANGE_RATES_TO_PEN_FXO_A (Cur_Id, TC)
	SELECT 
		C.Currencies_Id,
		Kustom.dbo.FUNC_CO_GET_AMOUNT_CCY_DAY(1, C.Currencies_Id, @PEN, @DIAHABIL)
	FROM @CURRENCIES_A C;
	
	
	UPDATE F
	SET [Precio Valor Actual] = (F.MarketValue * T.TC)
	FROM #FxOpt_AnexoA F
	INNER JOIN KplusLocal..Pairs P WITH(NOLOCK)
	ON P.Pairs_Id = F.Pairs_Id
	INNER JOIN @EXCHANGE_RATES_TO_PEN_FXO_A T
	ON T.Cur_Id = (CASE WHEN F.PremiumPayment = 1 THEN P.Currencies_Id_1 ELSE P.Currencies_Id_2 END)
	
	--Salida
	SELECT __TITLE__ 	  = 'Operaciones Opciones con ME'
	SELECT __ELEM_TITLE__ = 'ANEXO8AOPTME'+CONVERT(VARCHAR(8),@FECHAEJECUCION,112)
	SELECT __HEADER__     =	
							'Cuenta Contable'
							,'Por Cada Contrato u Operacion Vigente'
							,'Codigo de la operacion'
							,'Saldo Contable'
							,'Moneda pactada'
							,'Monto Nominal Pactado'
							,'Moneda entregada'
							,'Moneda recibida'
							,'Tipo de Opcion'
							,'Fecha de Inicio'
							,'Fecha de Vencimiento'
							,'Nombre'
							,'Residente / No Residente'
							,'Pais'
							,'Documento'
							,'Financiero / No Financiero'
							,'Codigo SBS'
							,'Codigo de deudor'
							,'Ponderacion por vencimiento residual (riesgo de credito)'
							,'Convenio marco de contratacion'
							,'Inicial'
							,'Al cierre en la fecha de reporte'
							,'Volatilidad del tipo de cambio'
							,'Tipo de Cambio Pactado'
							,'Prima Pagada'
							,'Delta'
							,'Gamma'
							,'Vega'
							,'Precio Valor Actual'
							,'Intencion de Contratacion'
							,'Partida Cubierta'
							,'Porcentaje de cobertura'
							,'Eficacia de Cobertura'
							,'Con delivery/ Sin delivery'
							,'Tasa de Interes al fijar precio Entregada'
							,'Tasa de Interes al fijar precio Recibida'
							,'Tasa de Interes a la fecha del reporte Entregada'
							,'Tasa de Interes a la fecha del reporte  Recibida'
							,'Descripcion'
							
	
	SELECT __FORMAT__=
							 NULL
							,NULL
							,NULL
							,'999 999 999 999 999 999.99'
							,NULL
							,'999 999 999 999 999 999.99'
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
							,NULL
							,NULL
							,'99.9999'
							,NULL
							,'99.9999'
							,'99.9999'
							,'99.9999'
							,'99.99'
							,'99.99'
							,'99.99999'
							,'99.99999'
							,'99.99999'
							,'999 999 999 999 999 999.99'
							,NULL
							,NULL
							,NULL
							,NULL
							,NULL
							,'999 999 999 999 999 999.99999'
							,'999 999 999 999 999 999.99999'
							,'999 999 999 999 999 999.99999'
							,'999 999 999 999 999 999.99999'
							,NULL

							
	SELECT 
							[Cuenta Contable],
							[Por Cada Contrato u Operacion Vigente],
							[Codigo de la operacion],
							[Saldo Contable],
							[Moneda pactada],
							[Monto Nominal Pactado],
							[Moneda entregada],
							[Moneda recibida],
							[Tipo de Opcion],
							[Fecha de Inicio],
							[Fecha de Vencimiento],
							[Nombre],
							[Residente / No Residente],
							[Pais],
							[Documento],
							[Financiero / No Financiero],
							[Codigo SBS],
							[Codigo de deudor],
							[Ponderacion por vencimiento residual (riesgo de credito)],
							[Convenio marco de contratacion],
							[Inicial],
							[Al cierre en la fecha de reporte],
							[Volatilidad del tipo de cambio ],
							[Tipo de Cambio Pactado],
							[Prima Pagada],
							[Delta],
							[Gamma],
							[Vega ],
							[Precio Valor Actual],
							[Intencion de Contratacion],
							[Partida Cubierta],
							[Porcentaje de cobertura],
							[Eficacia de Cobertura],
							[Con delivery/ Sin delivery],
							[Tasa de Interes al fijar precio Entregada],
							[Tasa de Interes al fijar precio Recibida],
							[Tasa de Interes a la fecha del reporte Entregada],
							[Tasa de Interes a la fecha del reporte  Recibida],
							[Descripcion]
	FROM #FxOpt_AnexoA
	
	--------------------------------------------------------------------
	-- A N E X O (A) : F X O P T I O N S  M. E.  
	--------------------------------------------------------------------
	--LM_KONDORG_14011: Fin


		SELECT __TITLE__ = 'Operaciones a Futuro de Tasas de Interes'
		SELECT __ELEM_TITLE__ = 'ANEXO8ASWPIR'+CONVERT(VARCHAR(8),@FECHAEJECUCION,112)
	/*==============Operaciones a Futuro de Tasas de Interes==============*/
SELECT
	'Cuenta Contable' = 													'8409.04.01'
	,'Por Cada Contrato u Operacion Vigente' = 								'Swaps de Tasas de Interes'
	,'Codigo de la operacion' = 											(CASE 	WHEN SWL.Indexation = 'F' AND SWD.Indexation = 'V'
																					THEN 'SWAPV'
																					WHEN SWL.Indexation = 'V' AND SWD.Indexation = 'F'
																					THEN 'SWAPC'
																			END) + (CASE 	WHEN LEFT(SWP.DownloadKey,1) <> '#'
																							THEN RIGHT(SWP.DownloadKey,4)
																							ELSE CONVERT(VARCHAR,SWP.SwapDeals_Id)
																					END)
	,'Saldo Contable' = 													CONVERT(DECIMAL(18,2),ISNULL((CASE	WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) = 'PEN')
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) IN ('USD','EUR','JPY','GBP'))
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWL.LegType
																																	AND		SWS.CashFlowType = 'I'
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC) * (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)), @PEN, @FECHAEJECUCION))
																												WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) IN ('USD','EUR','JPY','GBP'))
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'PEN')
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWD.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWD.LegType
																																	AND		SWS.CashFlowType = 'I'
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC) * (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType)), @PEN, @FECHAEJECUCION))
																												WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) = 'USD')
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) IN ('EUR','JPY','GBP'))
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWD.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWD.LegType
																																	AND		SWS.CashFlowType = 'I'
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC) * (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType)), @PEN, @FECHAEJECUCION))
																												WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) IN ('EUR','JPY','GBP'))
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'USD')
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWL.LegType
																																	AND		SWS.CashFlowType = 'I'
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC) * (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)), @PEN, @FECHAEJECUCION))
																												WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) = 'USD')
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'USD')
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWL.LegType
																																	AND		SWS.CashFlowType = 'I'
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC) * (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)), @PEN, @FECHAEJECUCION))
																												WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) IN ('EUR','JPY','GBP'))
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) IN ('EUR','JPY','GBP'))
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWL.LegType
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC) * (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)), @PEN, @FECHAEJECUCION))
																												WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) ='PEN')
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'PEN')
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWL.LegType
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC)
																											END),0))
	,'Moneda pactada' = 													(CASE	WHEN ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) = 'PEN')
																					AND	 ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) IN ('USD','EUR','JPY','GBP'))
																					THEN (SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)))
																					WHEN ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) IN ('USD','EUR','JPY','GBP'))
																					AND	 ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'PEN')
																					THEN (SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType)))
																					WHEN ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) = 'USD')
																					AND	 ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) IN ('EUR','JPY','GBP'))
																					THEN (SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType)))
																					WHEN ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) IN ('EUR','JPY','GBP'))
																					AND	 ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'USD')
																					THEN (SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)))
																					WHEN ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) = 'USD')
																					AND	 ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'USD')
																					THEN (SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)))
																					WHEN ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) IN ('EUR','JPY','GBP'))
																					AND	 ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) IN ('EUR','JPY','GBP'))
																					THEN (SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)))
																					WHEN ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) ='PEN')
																					AND	 ((SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'PEN')
																					THEN (SELECT Currencies_ShortName
																							FROM KplusLocal..Currencies WITH(NOLOCK)
																							WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)))
																			END)
	,'Monto Nominal Pactado' = 												CONVERT(DECIMAL(18,2),ISNULL((CASE	WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) = 'PEN')
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) IN ('USD','EUR','JPY','GBP'))
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWL.LegType
																																	AND		SWS.CashFlowType = 'I'
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC)
																												WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) IN ('USD','EUR','JPY','GBP'))
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'PEN')
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWD.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWD.LegType
																																	AND		SWS.CashFlowType = 'I'
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC)
																												WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) = 'USD')
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) IN ('EUR','JPY','GBP'))
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWD.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWD.LegType
																																	AND		SWS.CashFlowType = 'I'
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC)
																												WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) IN ('EUR','JPY','GBP'))
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'USD')
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWL.LegType
																																	AND		SWS.CashFlowType = 'I'
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC)
																												WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) = 'USD')
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'USD')
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWL.LegType
																																	AND		SWS.CashFlowType = 'I'
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC)
																												WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) IN ('EUR','JPY','GBP'))
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) IN ('EUR','JPY','GBP'))
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWL.LegType
																																	AND		SWS.CashFlowType = 'I'
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC)
																												WHEN ((SELECT Currencies_ShortName
																														FROM KplusLocal..Currencies WITH(NOLOCK)
																														WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) ='PEN')
																														AND	 ((SELECT Currencies_ShortName
																																FROM KplusLocal..Currencies WITH(NOLOCK)
																																WHERE Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'PEN')
																														THEN (SELECT TOP 1 SWS.Principal
																																	FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																																	WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																																	AND		SWS.ScheduleLeg = SWL.LegType
																																	AND		SWS.CashFlowType = 'I'
																																	AND		DATEDIFF(DAY,SWS.EndDate,@FECHAEJECUCION) < 0
																																	ORDER BY SWS.EndDate ASC)
																											END),0))
	,'Posicion larga a Valor de Mercado' = 							CONVERT(DECIMAL(18,2), (CASE 	WHEN ((SELECT 	Currencies_ShortName
																													FROM 	KplusLocal..Currencies WITH(NOLOCK)
																													WHERE 	Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) = 'USD')
																											THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)), @PEN, @DIAHABIL))
																											ELSE 1
																											END) * ISNULL( ABS((SELECT 	MTM_L
																																		FROM	@TBL_PE_MTM_SWAP MTMSWP
																																		WHERE 	MTMSWP.SwapDeals_Id = SWL.SwapDeals_Id
																																		AND		DATEDIFF ( DAY, MTMSWP.Fecha_Reporte, @DIAHABIL) = 0)),0))
	,'Duracion de Macaulay posicion larga' =                                CONVERT(DECIMAL(8,4),ISNULL( ABS((SELECT 	SUM(RiskData_Duration)
																											FROM 	DataKondorPE..TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
																											WHERE	SwapDeals_SwapDeals_Id = SWL.SwapDeals_Id
																											AND		LEFT(SwapLegCurrent_LegType,1) = 'L'
																											AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0)),0))
	,'Duracion modificada posicion larga' =                                 CONVERT(DECIMAL(8,4),ISNULL( ABS((SELECT 	SUM(RiskData_ModDuration)
																											FROM 	DataKondorPE..TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
																											WHERE	SwapDeals_SwapDeals_Id = SWL.SwapDeals_Id
																											AND		LEFT(SwapLegCurrent_LegType,1) = 'L'
																											AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0)),0))
	,'Posicion corta a Valor de Mercado' =                         CONVERT(DECIMAL(18,2), (CASE 	WHEN ((SELECT 	Currencies_ShortName
																													FROM 	KplusLocal..Currencies WITH(NOLOCK)
																													WHERE 	Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'USD')
																											THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType)), @PEN, @DIAHABIL))
																											ELSE 1
																											END) * ISNULL( ABS((SELECT 	MTM_D
																																		FROM	@TBL_PE_MTM_SWAP MTMSWP
																																		WHERE 	MTMSWP.SwapDeals_Id = SWD.SwapDeals_Id
																																		AND		DATEDIFF ( DAY, MTMSWP.Fecha_Reporte, @DIAHABIL) = 0)),0))
	,'Duracion de Macaulay posicion corta' =                                CONVERT(DECIMAL(8,4),ABS(ISNULL( (SELECT 	SUM(RiskData_Duration)
																											FROM 	DataKondorPE..TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
																											WHERE	SwapDeals_SwapDeals_Id = SWL.SwapDeals_Id
																											AND		LEFT(SwapLegCurrent_LegType,1) = 'D'
																											AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0),0)))
	,'Duracion modificada posicion corta' =                                 CONVERT(DECIMAL(8,4),ABS(ISNULL( (SELECT 	SUM(RiskData_ModDuration)
																											FROM 	DataKondorPE..TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
																											WHERE	SwapDeals_SwapDeals_Id = SWL.SwapDeals_Id
																											AND		LEFT(SwapLegCurrent_LegType,1) = 'D'
																											AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0),0)))

/*Descripcion de la Operacion*/
	,'Tasas de Interes entregada' = 										(CASE 	WHEN SWD.Indexation = 'F'
																					THEN 'FIJA'
																					ELSE (SELECT FR.FloatingRates_Name
																						 FROM 	KplusLocal..FloatingRates FR WITH(NOLOCK)
																						 WHERE 	FR.FloatingRates_Id = SWD.FloatingRates_Id)
																			END)
	,'Tasas de Interes recibida' = 											(CASE 	WHEN SWL.Indexation = 'F'
																					THEN 'FIJA'
																					ELSE (SELECT FR.FloatingRates_Name
																						 FROM 	KplusLocal..FloatingRates FR WITH(NOLOCK)
																						 WHERE 	FR.FloatingRates_Id = SWL.FloatingRates_Id)
																			END)
	,'Moneda' =																(SELECT 	Currencies_ShortName
																				FROM	KplusLocal..Currencies WITH(NOLOCK)
																				WHERE	Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)))
	,'Fecha de Inicio' = 													CONVERT(DATE,SWP.TradeDate)
	,'Fecha de Vencimiento' =                                               CONVERT(DATE,SWL.MaturityDate)

/*Contraparte*/
	,'Nombre' = 															Cy.Cpty_Name
	,'Residente / No Residente' = 											(CASE 	WHEN Cy.IsResident = 'Y'
																					THEN 'R'
																					ELSE 'NR'
																					END)
	,'Pais' = 																(SELECT 	Ci.Cities_ShortName
																						FROM KplusLocal..Cities Ci WITH(NOLOCK)
																						WHERE Cy.Cities_Id = Ci.Cities_Id)
	,'Documento' = 															(CASE	WHEN CyPE.Documento IS NOT NULL
																			THEN CONVERT(VARCHAR,CyPE.Documento)
																			ELSE 'NOSCCATT'
																			END)
	,'Financiero / No Financiero' = 										ISNULL((CASE 	WHEN CyC.CptyClasses_ShortName = 'AFP'
																							THEN 'AFP'
																							WHEN CyC.CptyClasses_ShortName IN ('EMP_BANCAR','EMP_FINANC','SAB','OTRS_EMP_F','BCOS_EXTER','FONDOS_MUT','FONDOS_PUB','SOC_AG_BOL','EMP_ARR_FI')
																							THEN 'F'
																							ELSE 'NF'
																					END),'NF')
	,'Codigo SBS' = 														ISNULL(CyPE.CodigoSBS,0)
	,'Codigo de deudor' = 													Cy.Cpty_ShortName
	,'Ponderacion por vencimiento residual (riesgo de credito)' = 			(CASE 	WHEN ROUND(Kustom.dbo.FUNC_TIEMPOEXACTO(@FECHAEJECUCION,SWL.MaturityDate,'Y'),0) < 1
																					THEN 0
																					ELSE 0.5
																					END)/100 +
																			(CASE 	WHEN ROUND(Kustom.dbo.FUNC_TIEMPOEXACTO(@FECHAEJECUCION,SWL.MaturityDate,'Y')-5,0) < 1
																					THEN 0
																					ELSE ROUND(Kustom.dbo.FUNC_TIEMPOEXACTO(@FECHAEJECUCION,SWL.MaturityDate,'Y')-5,0)
																			END) * 1.5/100
	,'Convenio marco de contratacion' = 									ISNULL(( CASE	WHEN CyPE.CM_DRV = 'Y'
																					THEN 'S'
																					ELSE 'N'
																					END),'N')

/*Tasa Anual Spot (Tasa entregada)*/
	,'Inicial' = 															ISNULL(CONVERT(DECIMAL(8,4),(CASE 	WHEN SWD.Indexation = 'F'
																												THEN SWD.FixedRate
																												ELSE (SELECT FRV.Rate
																														FROM	KplusLocal..FloatingRatesValues FRV WITH(NOLOCK)
																														WHERE 	SWD.FloatingRates_Id = FRV.FloatingRates_Id
																														AND		DATEDIFF(DAY,FRV.FRDate,SWP.TradeDate) = 0) +
																													(SWD.AdditiveMargin/100)
																			END))/100,0)
	,'Al cierre en la fecha de reporte' = 									ISNULL(CONVERT(DECIMAL(8,4),(CASE 	WHEN SWD.Indexation = 'F'
																												THEN SWD.FixedRate
																												ELSE ((SELECT FRV.Rate
																														FROM	KplusLocal..FloatingRatesValues FRV WITH(NOLOCK)
																														WHERE 	SWD.FloatingRates_Id = FRV.FloatingRates_Id
																														AND		DATEDIFF(DAY,FRV.FRDate,@FECHAEJECUCION) = 0)) +
																													(SWD.AdditiveMargin/100)
																			END))/100,0)

/*Tasa Anual Spot (Tasa recibida)*/
	,'Inicial' = 															ISNULL(CONVERT(DECIMAL(8,4),(CASE 	WHEN SWL.Indexation = 'F'
																												THEN SWL.FixedRate
																												ELSE (SELECT FRV.Rate
																														FROM	KplusLocal..FloatingRatesValues FRV WITH(NOLOCK)
																														WHERE 	SWL.FloatingRates_Id = FRV.FloatingRates_Id
																														AND		DATEDIFF(DAY,FRV.FRDate,SWP.TradeDate) = 0) +
																													(SWL.AdditiveMargin/100)
																			END))/100,0)
	,'Al cierre en la fecha de reporte' = 									ISNULL(CONVERT(DECIMAL(8,4),(CASE 	WHEN SWL.Indexation = 'F'
																												THEN SWL.FixedRate
																												ELSE ((SELECT FRV.Rate
																														FROM	KplusLocal..FloatingRatesValues FRV WITH(NOLOCK)
																														WHERE 	SWL.FloatingRates_Id = FRV.FloatingRates_Id
																														AND		DATEDIFF(DAY,FRV.FRDate,@FECHAEJECUCION) = 0)) +
																													(SWL.AdditiveMargin/100)
																			END))/100,0)

/*Tasas Anuales Pactadas*/
	,'Tasa Entregada' = 													ISNULL(CONVERT(DECIMAL(8,4),(CASE 	WHEN SWD.Indexation = 'F'
																												THEN SWD.FixedRate
																												ELSE (SELECT FRV.Rate
																														FROM	KplusLocal..FloatingRatesValues FRV WITH(NOLOCK)
																														WHERE 	SWD.FloatingRates_Id = FRV.FloatingRates_Id
																														AND		DATEDIFF(DAY,FRV.FRDate,SWP.TradeDate) = 0) +
																													(SWD.AdditiveMargin/100)
																			END))/100,0)
	,'Tasa Recibida' = 														ISNULL(CONVERT(DECIMAL(8,4),(CASE 	WHEN SWL.Indexation = 'F'
																												THEN SWL.FixedRate
																												ELSE (SELECT FRV.Rate
																														FROM	KplusLocal..FloatingRatesValues FRV WITH(NOLOCK)
																														WHERE 	SWL.FloatingRates_Id = FRV.FloatingRates_Id
																														AND		DATEDIFF(DAY,FRV.FRDate,SWP.TradeDate) = 0) +
																													(SWL.AdditiveMargin/100)
																			END))/100,0)
	,'Valor de Mercado (Valor Actual)' = 							CONVERT(DECIMAL(18,2), (CASE 	WHEN ((SELECT 	Currencies_ShortName
																													FROM 	KplusLocal..Currencies WITH(NOLOCK)
																													WHERE 	Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))) = 'USD')
																											THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType)), @PEN, @DIAHABIL))
																											ELSE 1
																											END) * ISNULL( (SELECT 	MTM_L
																																		FROM	@TBL_PE_MTM_SWAP MTMSWP
																																		WHERE 	MTMSWP.SwapDeals_Id = SWL.SwapDeals_Id
																																		AND		DATEDIFF ( DAY, MTMSWP.Fecha_Reporte, @DIAHABIL) = 0),0))
																	+
																	CONVERT(DECIMAL(18,2), (CASE 	WHEN ((SELECT 	Currencies_ShortName
																													FROM 	KplusLocal..Currencies WITH(NOLOCK)
																													WHERE 	Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))) = 'USD')
																											THEN (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType)), @PEN, @DIAHABIL))
																											ELSE 1
																											END) * ISNULL( (SELECT 	MTM_D
																																		FROM	@TBL_PE_MTM_SWAP MTMSWP
																																		WHERE 	MTMSWP.SwapDeals_Id = SWD.SwapDeals_Id
																																		AND		DATEDIFF ( DAY, MTMSWP.Fecha_Reporte, @DIAHABIL) = 0),0))
	,'Intencion de Contratacion' = 											(CASE 	WHEN LEFT(F.Folders_ShortName,4) = 'TRAD'
																					THEN 'N'
																					WHEN LEFT(F.Folders_ShortName,3) = 'ALM'
																					THEN 'CC'
																			END)

/*Cobertura del Instrumento*/
	,'Partida Cubierta' = 													''--ISNULL(SWPCob.PARTIDA_CUBIERTA,'')
	,'Porcentaje de cobertura' =                                            ''--ISNULL(SWPCob.PORCENTAJE_COBERTURA,0)
	,'Eficacia de Cobertura' =                                              ''--ISNULL(SWPCob.EFICACIA_COBERTURA,0)

/*Forma de Pago*/
	,'Con delivery/ Sin delivery' = 										(CASE	WHEN Kustom.dbo.FUNC_DRV_SWAP_Delivery_Mode(SWP.SwapDeals_Id) = 'D'
																					THEN 'Delivery'
																					ELSE 'Sin Delivery'
																			END)
	,'Descripcion' =												''
	,' ' =															''
	,'Codigo BT' = 													Cy.Cpty_ShortName
	,'Codigo Cartera' = 											(CASE 	WHEN LEFT(SWP.DownloadKey,1) <> '#'
																			THEN RIGHT(SWP.DownloadKey,3)
																			ELSE CONVERT(VARCHAR,SWP.SwapDeals_Id)
																	END)
FROM 		KplusLocal..SwapDeals SWP WITH(NOLOCK)
INNER JOIN	@RTK_SWP_DEALS RTKSWP
	ON		SWP.SwapDeals_Id = RTKSWP.SwapDeals_Id
INNER JOIN 	KplusLocal..SwapLeg SWL WITH(NOLOCK)
	ON 			SWP.SwapDeals_Id = SWL.SwapDeals_Id
	AND 		SWL.LegType = 'L'
INNER JOIN 	KplusLocal..SwapLeg SWD WITH(NOLOCK)
	ON 			SWP.SwapDeals_Id = SWD.SwapDeals_Id
	AND 		SWD.LegType  = 'D'
INNER JOIN	KplusLocal..Currencies CUL WITH(NOLOCK)
	ON 			CUL.Currencies_Id = SWL.Currencies_Id
INNER JOIN	KplusLocal..Currencies CUD WITH(NOLOCK)
	ON 			CUD.Currencies_Id = SWD.Currencies_Id
INNER JOIN	KplusLocal..Folders F WITH(NOLOCK)
	ON 			F.Folders_Id = SWL.Folders_Id
INNER JOIN  Kustom..TBL_REG_SCOTIAZONE_HIERARCHY	TBL_H WITH(NOLOCK)
	ON 			SWL.Folders_Id = TBL_H.Folders_Id
	AND 		TBL_H.Regions_Id = @Regions_Id
INNER JOIN	KplusLocal..TypeOfInstr TY WITH(NOLOCK)
	ON 			SWL.TypeOfInstr_Id = TY.TypeOfInstr_Id
INNER JOIN	KplusLocal..Cpty Cy WITH(NOLOCK)
	ON 			Cy.Cpty_Id = SWL.Cpty_Id
	AND 		TY.TypeOfInstr_ShortName IN ('IRS')
	AND			SWP.DealStatus		IN ('V')
	AND 		SWP.InputMode		NOT IN	('G')
	AND 		SWP.TypeOfEvent		NOT IN 	('M','L')
	AND			DATEDIFF(DAY,SWP.TradeDate,@FECHAEJECUCION) >= 0
	AND			DATEDIFF(DAY,ISNULL(SWP.LiquidationDate,SWL.MaturityDate),@FECHAEJECUCION)     < 0
	AND			SWL.Indexation <> SWD.Indexation
--AND 		SWP.SwapDeals_Id NOT IN (27015)
--LEFT JOIN	Kustom..TBL_PE_DRV_SWP_COBERTURA SWPCob
--	ON			SWPCob.DealId = SWP.SwapDeals_Id
--	AND 		SWPCob.DealType = 'SwapDeals'
LEFT JOIN	Kustom.dbo.TBL_PE_CPTY_CUSTOM	CyPE WITH(NOLOCK)
	ON 			Cy.Cpty_Id = CyPE.DealId
LEFT JOIN	KplusLocal..CptyClasses CyC WITH(NOLOCK)
	ON			CyC.CptyClasses_Id = Cy.CptyClasses_Id

END

	ELSE

IF	(@AnexoId='B')
BEGIN

DECLARE @RTK_FWD_DEALS TABLE (
ForwardDeals_Id	INT
,FwdRate				DECIMAL(14,6)
,Moneda				VARCHAR(3)
,Valor_Razonable	DECIMAL(18,2)
,Posicion			VARCHAR(7)
)

DECLARE @RTK_SWAP_DEALS TABLE (
SwapDeals_Id		INT
,InstrumentName	VARCHAR(20)
,PosicionInterna	VARCHAR(10)
)

DECLARE @COMPRAVENTASWP TABLE(
SwapDeals_Id		INT
,COMPRAVENTASWP		VARCHAR(17)
)

INSERT INTO @RTK_FWD_DEALS
SELECT DISTINCT
'ForwardDeals_Id'		= RTKFWD.ForwardDeals_ForwardDeals_Id
,'FwdRate'				= CONVERT(DECIMAL(14,6),FWD.InterestRateCur1)
,'Moneda'				= Cu1.Currencies_ShortName
,'Valor_Razonable'	= RTKFWD.Npv_Leg_PEN
,'Posicion'				= (CASE 	WHEN FWD.Amount1>=0
										THEN 'LARGA'
										ELSE 'CORTA'
								END)
FROM 			KplusLocal..ForwardDeals FWD WITH(NOLOCK)
INNER JOIN	DataKondorPE.dbo.TBL_PE_RTK_FX_FWD_HIST RTKFWD WITH(NOLOCK)
ON				RTKFWD.ForwardDeals_ForwardDeals_Id = FWD.ForwardDeals_Id
AND				RTKFWD.ValuationData_Folder_ShortName != 'SAL_FWDSTR'	--FM202403
INNER JOIN 	KplusLocal..Pairs Pa WITH(NOLOCK)
ON				FWD.Pairs_Id = Pa.Pairs_Id
INNER JOIN	KplusLocal..Currencies Cu1 WITH(NOLOCK)
ON				Cu1.Currencies_Id = Pa.Currencies_Id_1
INNER JOIN	KplusLocal..Currencies Cu2 WITH(NOLOCK)
ON 			Cu2.Currencies_Id = Pa.Currencies_Id_2
AND			DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0
AND			RTKFWD.ValuationData_Currencies_Short = Cu1.Currencies_ShortName

INSERT INTO @RTK_FWD_DEALS
SELECT DISTINCT
'ForwardDeals_Id'		= RTKFWD.ForwardDeals_ForwardDeals_Id
,'FwdRate'				= CONVERT(DECIMAL(14,6),FWD.InterestRateCur2)
,'Moneda'				= Cu2.Currencies_ShortName
,'Valor_Razonable'	= RTKFWD.Npv_Leg_PEN
,'Posicion'				= (CASE 	WHEN FWD.Amount2>=0
										THEN 'LARGA'
										ELSE 'CORTA'
								END)
FROM 			KplusLocal..ForwardDeals FWD WITH(NOLOCK)
INNER JOIN	DataKondorPE..TBL_PE_RTK_FWD_MID RTKFWD WITH(NOLOCK)
ON				RTKFWD.ForwardDeals_ForwardDeals_Id = FWD.ForwardDeals_Id
AND				RTKFWD.ValuationData_Folder_ShortName != 'SAL_FWDSTR'	--FM202403
INNER JOIN 	KplusLocal..Pairs Pa WITH(NOLOCK)
ON				FWD.Pairs_Id = Pa.Pairs_Id
INNER JOIN	KplusLocal..Currencies Cu1 WITH(NOLOCK)
ON				Cu1.Currencies_Id = Pa.Currencies_Id_1
INNER JOIN	KplusLocal..Currencies Cu2 WITH(NOLOCK)
ON 			Cu2.Currencies_Id = Pa.Currencies_Id_2
AND			DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0
AND			RTKFWD.ValuationData_Currencies_Short = Cu2.Currencies_ShortName

--select * from @RTK_FWD_DEALS

INSERT INTO @RTK_SWAP_DEALS
SELECT DISTINCT
SwapDeals_SwapDeals_Id
,StaticData_TypeOfInstrShortNam
,(CASE	WHEN StaticData_CptyShortName LIKE '[^A-Z]%'
			THEN ''
			ELSE 'Interno'
	END)
FROM 	DataKondorPE.dbo.TBL_PE_RTK_SWP_HIST WITH(NOLOCK) --TBL_PE_RTK_SWP_HIST
WHERE DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0

--SELECT * FROM @RTK_SWAP_DEALS

INSERT INTO @COMPRAVENTASWP
SELECT
'Deal_Id' =	SWL.SwapDeals_Id
,'Signo_Operacion' =	(CASE	WHEN TY.TypeOfInstr_ShortName  IN ('IRS','OIS')
								THEN (CASE 	WHEN SWL.Indexation = 'F' AND SWD.Indexation = 'V'
												THEN 'SWAPV'
												WHEN SWL.Indexation = 'V' AND SWD.Indexation = 'F'
												THEN 'SWAPC'
										END) + (CASE 	WHEN LEFT(SWP.DownloadKey,1) <> '#'
															THEN RIGHT(SWP.DownloadKey,4)
															ELSE CONVERT(VARCHAR,SWP.SwapDeals_Id)
												END)
								ELSE
							(CASE	WHEN (CULP.Currencies_ShortName = 'PEN') AND (CUDP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
									THEN 'SWAPV'
									WHEN (CUDP.Currencies_ShortName = 'PEN') AND (CULP.Currencies_ShortName IN ('USD','EUR','JPY','GBP'))
									THEN 'SWAPC'
									WHEN (CULP.Currencies_ShortName = 'USD') AND (CUDP.Currencies_ShortName IN ('EUR','JPY','GBP'))
									THEN 'SWAPV'
									WHEN (CUDP.Currencies_ShortName = 'USD') AND (CULP.Currencies_ShortName IN ('EUR','JPY','GBP'))
									THEN 'SWAPC'
							END) + (CASE 	WHEN LEFT(SWP.DownloadKey,1) <> '#'
											THEN RIGHT(SWP.DownloadKey,5)
											ELSE CONVERT(VARCHAR,SWP.SwapDeals_Id)
									END)
						END)
FROM 		KplusLocal..SwapDeals SWP WITH(NOLOCK)
INNER JOIN	@RTK_SWAP_DEALS RTKS
	ON			RTKS.SwapDeals_Id = SWP.SwapDeals_Id
INNER JOIN 	KplusLocal..SwapLeg SWL WITH(NOLOCK)
	ON 			SWP.SwapDeals_Id = SWL.SwapDeals_Id
	AND 		SWL.LegType = 'L'
INNER JOIN 	KplusLocal..SwapLeg SWD WITH(NOLOCK)
	ON 			SWP.SwapDeals_Id = SWD.SwapDeals_Id
	AND 		SWD.LegType  = 'D'
INNER JOIN	KplusLocal..Currencies CUL WITH(NOLOCK)
	ON 			CUL.Currencies_Id = SWL.Currencies_Id
INNER JOIN	KplusLocal..Currencies CUD WITH(NOLOCK)
	ON 			CUD.Currencies_Id = SWD.Currencies_Id
INNER JOIN	KplusLocal..Currencies CULP WITH(NOLOCK)
	ON 			CULP.Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))
INNER JOIN	KplusLocal..Currencies CUDP WITH(NOLOCK)
	ON 			CUDP.Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWD.SwapDeals_Id,SWD.LegType))
INNER JOIN	KplusLocal..Folders F WITH(NOLOCK)
	ON 			F.Folders_Id = SWL.Folders_Id
INNER JOIN  Kustom..TBL_REG_SCOTIAZONE_HIERARCHY	TBL_H WITH(NOLOCK)
	ON 			SWL.Folders_Id = TBL_H.Folders_Id
--	AND 		TBL_H.Regions_Id = @Regions_Id
INNER JOIN	KplusLocal..TypeOfInstr TY WITH(NOLOCK)
	ON 			SWL.TypeOfInstr_Id = TY.TypeOfInstr_Id
--	AND			SWP.DealStatus		IN ('V')
--	AND 		SWP.InputMode		NOT IN	('G')
--	AND 		SWP.TypeOfEvent		NOT IN 	('M')
--	AND			DATEDIFF(DAY,SWP.TradeDate,@FECHAEJECUCION) >= 0
--	AND			DATEDIFF(DAY,ISNULL(SWP.LiquidationDate,SWL.MaturityDate),@FECHAEJECUCION)     < 0


		SELECT __TITLE__ = 'Forward de Moneda'
		SELECT __ELEM_TITLE__ = 'ANEXO8BFWDME'+CONVERT(VARCHAR(8),@FECHAEJECUCION,112)
		SELECT __HEADER__     =
		'Grupo de compensacion'
		,'Codigo de operacion'
		,'Cpty_Nombre'
		,'Cpty_Pais'
		,'Cpty_Documento'
		,'Cpty_Codigo SBS'
		,'Vencimiento residual'
		,'Rango de vencimiento'
		,'Tasa entregada/recibida'
		,'Moneda entregada/recibida'
		,'Valor razonable'
		,'Tipo de posicion'

		SELECT __FORMAT__=
		NULL
		,NULL
		,NULL
		,NULL
		,NULL
		,NULL
		,'999 999 999'
		,'999 999 999'
		,'-999 999 999.9999'
		,NULL
		,'-999 999 999 999.99'
		,NULL

	/*==============Forward de Moneda==============*/

SELECT
	'Grupo_compensacion'		= MEFS.CompesationGroup
	,'Codigo_operacion'		= (CASE	WHEN FWD.Amount1>=0
												THEN 'FWDC'
												ELSE 'FWDV'
										END) + (CASE 	WHEN LEFT(FWD.DownloadKey,1) <> '#'
															THEN SUBSTRING(FWD.DownloadKey,4,16)
															ELSE CONVERT(VARCHAR,FWD.ForwardDeals_Id) + (CASE	WHEN FWD.ForwardDeals_Id>(SELECT ValorInt FROM Kustom..TBL_PARAMETROS_LOCAL_APP WITH(NOLOCK) WHERE IdGlobal = 'PE_FWD_LAST_ID_95')
																																THEN ''
																																ELSE '95'
																														END)
													END)
/*Contraparte*/
	,'Nombre'					= ISNULL(Cy.Cpty_Name,'')
	,'Pais'						= ISNULL((SELECT 	Ci.Cities_ShortName
													FROM KplusLocal..Cities Ci WITH(NOLOCK)
													WHERE Cy.Cities_Id = Ci.Cities_Id),'PE')
	,'Documento'				= ISNULL((CASE	WHEN CyPE.Documento IS NOT NULL
														THEN CONVERT(VARCHAR,CyPE.Documento)
														ELSE 'NOSCCATT'
												END),'')
	,'Codigo_SBS'				= ISNULL(CyPE.CodigoSBS,0)

	,'Vencimiento_residual' =  DATEDIFF(DAY,@FECHAEJECUCION,ISNULL(FWD.LiquidationDate,FWD.MaturityDate))
	,'Rango_vencimiento'		=	0
	,'Tasa'						=	RTK.FwdRate
	,'Moneda'					=	RTK.Moneda
	,'Valor_Razonable'		=	CONVERT(DECIMAL(18,2),ISNULL(ABS(RTK.Valor_Razonable),0))
	,'Tipo_Posicion'			= MEFS.PositionType
 INTO #A8BFWDME
FROM			DataKondorPE.dbo.TBL_PE_MOTOR_EMPAREJAMIENTO_FWD_SWP MEFS WITH(NOLOCK)
INNER JOIN	KplusLocal..ForwardDeals		FWD WITH(NOLOCK)
	ON		FWD.ForwardDeals_Id = MEFS.Deal_Id
	AND	(FWD.LiquidationDate IS NULL OR FWD.ForwardType <> 'N' OR @FECHAEJECUCION < FWD.LiquidationDate) --VP202408
INNER JOIN	@RTK_FWD_DEALS						RTK
	ON		RTK.ForwardDeals_Id = FWD.ForwardDeals_Id
	AND	RTK.Posicion = MEFS.PositionType
INNER JOIN 	KplusLocal..Pairs					Pa WITH(NOLOCK)
	ON		FWD.Pairs_Id = Pa.Pairs_Id
INNER JOIN	KplusLocal..Currencies			Cu1 WITH(NOLOCK)
	ON		Cu1.Currencies_Id = Pa.Currencies_Id_1
INNER JOIN	KplusLocal..Currencies			Cu2 WITH(NOLOCK)
ON			Cu2.Currencies_Id = Pa.Currencies_Id_2
INNER JOIN	KplusLocal..Cpty					Cy WITH(NOLOCK)
	ON		Cy.Cpty_Id = FWD.Cpty_Id
	AND	DATEDIFF(DAY,MEFS.Fecha,@FECHAEJECUCION) = 0
	AND	InstrumentType	= 'ForwardDeals'
	AND	CompesationGroup <> 0
LEFT JOIN	Kustom.dbo.TBL_PE_CPTY_CUSTOM	CyPE WITH(NOLOCK)
	ON		Cy.Cpty_Id = CyPE.DealId
LEFT JOIN	KplusLocal..CptyClasses			CyC WITH(NOLOCK)
ON			CyC.CptyClasses_Id = Cy.CptyClasses_Id
ORDER BY CompesationGroup ASC


SELECT	Grupo_compensacion
		,'Rango_vencimiento' = MAX(Vencimiento_residual) - MIN (Vencimiento_residual)
INTO #RGOVENC
FROM #A8BFWDME
GROUP BY Grupo_compensacion

SELECT	A.Grupo_compensacion
		,A.Codigo_operacion
		,A.Nombre
		,A.Pais
		,A.Documento
		,A.Codigo_SBS
		,A.Vencimiento_residual
		,B.Rango_vencimiento
		,A.Tasa
		,A.Moneda
		,A.Valor_Razonable
		,A.Tipo_Posicion
FROM #A8BFWDME A
INNER JOIN #RGOVENC B
ON A.Grupo_compensacion = B.Grupo_compensacion
ORDER BY 1 ASC

DROP TABLE #A8BFWDME
DROP TABLE #RGOVENC

		SELECT __TITLE__ = 'Swaps de Moneda'
		SELECT __ELEM_TITLE__ = 'ANEXO8BSWPME'+CONVERT(VARCHAR(8),@FECHAEJECUCION,112)
		SELECT __HEADER__     =
		'Grupo de compensacion'
		,'Codigo de operacion'
		,'Cpty_Nombre'
		,'Cpty_Pais'
		,'Cpty_Documento'
		,'Cpty_Codigo SBS'
		,'Vencimiento residual'
		,'Proxima fecha de reprecio'
		,'Rango de vencimiento'
		,'Tasa entregada/recibida'
		,'Moneda entregada/recibida'
		,'Valor razonable'
		,'Tipo de posicion'

		SELECT __FORMAT__=
		NULL
		,NULL
		,NULL
		,NULL
		,NULL
		,NULL
		,'999 999 999'
		,NULL
		,'999 999 999'
		,'-999 999 999.9999'
		,NULL
		,'-999 999 999 999.99'
		,NULL

	/*==============Swaps de Moneda==============*/
SELECT
	'Grupo de compensacion'			= MEFS.CompesationGroup
	,'Codigo de operacion'			= CVSWP.COMPRAVENTASWP
/*Contraparte*/
	,'Nombre'							= ISNULL(Cy.Cpty_Name,'')
	,'Pais'								= ISNULL((SELECT 	Ci.Cities_ShortName
															FROM KplusLocal..Cities Ci WITH(NOLOCK)
															WHERE Cy.Cities_Id = Ci.Cities_Id),'PE')
	,'Documento'						= ISNULL((CASE	WHEN CyPE.Documento IS NOT NULL
																THEN CONVERT(VARCHAR,CyPE.Documento)
																ELSE 'NOSCCATT'
														END),'')
	,'Codigo SBS'						= ISNULL(CyPE.CodigoSBS,0)

	,'Vencimiento residual'			= DATEDIFF(DAY,@FECHAEJECUCION,SWL.MaturityDate)
	,'Proxima fecha de reprecio'	= CONVERT(DATE,ISNULL((CASE	WHEN SWL.Indexation = 'F'
																					THEN SWL.MaturityDate
																					ELSE (SELECT TOP 1 SWS.FixingDate
																							FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																							WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																							AND		SWS.ScheduleLeg = SWL.LegType
																							AND		DATEDIFF(DAY,SWS.FixingDate,@FECHAEJECUCION) <= 0
																							ORDER BY SWS.FixingDate ASC)
																			END),SWL.MaturityDate))
	,'Rango de vencimiento'			= 1
	,'Tasa entregada/recibida'		= ISNULL(CONVERT(DECIMAL(8,4),(CASE 	WHEN SWL.Indexation = 'F'
																								THEN SWL.FixedRate
																								ELSE (SELECT FRV.Rate
																										FROM	KplusLocal..FloatingRatesValues FRV WITH(NOLOCK)
																										WHERE 	SWL.FloatingRates_Id = FRV.FloatingRates_Id
																										AND		DATEDIFF(DAY,FRV.FRDate,@FECHAEJECUCION) = 0)  +
																									(SWL.AdditiveMargin/100)
																						END)),0)/100
	,'Moneda entregada/recibida'	= CU.Currencies_ShortName
	,'Valor razonable'				= (CASE	WHEN CU.Currencies_ShortName = 'USD'
														THEN
														CONVERT(DECIMAL(18,2),CONVERT(DECIMAL(18,2),ISNULL( (SELECT 	SUM(RawPLData_Npv)
																						FROM 	DataKondorPE..TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
																						WHERE	SwapDeals_SwapDeals_Id = MEFS.Deal_Id
																						AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0),0)) * (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, CU.Currencies_Id, @PEN, @FECHAEJECUCION)))
														ELSE
														CONVERT(DECIMAL(18,2),CONVERT(DECIMAL(18,2),ISNULL( (SELECT 	SUM(RawPLData_Npv)
																						FROM 	DataKondorPE..TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
																						WHERE	SwapDeals_SwapDeals_Id = MEFS.Deal_Id
																						AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0),0)))
												END)
	,'Tipo de posicion'				=	MEFS.PositionType
FROM	DataKondorPE.dbo.TBL_PE_MOTOR_EMPAREJAMIENTO_FWD_SWP MEFS WITH(NOLOCK)
INNER JOIN @COMPRAVENTASWP CVSWP
	ON		CVSWP.SwapDeals_Id = MEFS.Deal_Id
INNER JOIN KplusLocal..SwapLeg SWL WITH(NOLOCK)
	ON		SWL.SwapDeals_Id = MEFS.Deal_Id
	AND	SWL.LegType = (CASE 	WHEN MEFS.PositionType = 'LARGA'
										THEN 'L'
										ELSE 'D'
								END)
INNER JOIN KplusLocal..Cpty Cy WITH(NOLOCK)
	ON		Cy.Cpty_Id = SWL.Cpty_Id
INNER JOIN KplusLocal..Currencies CU WITH(NOLOCK)
	ON		CU.Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))
	AND	DATEDIFF(DAY,MEFS.Fecha,@FECHAEJECUCION) = 0
	AND	InstrumentType	= 'SwapDeals'
	AND	InstrumentName = 'CCS'
	AND	CompesationGroup <> 0
LEFT JOIN Kustom.dbo.TBL_PE_CPTY_CUSTOM	CyPE WITH(NOLOCK)
	ON		Cy.Cpty_Id = CyPE.DealId
LEFT JOIN KplusLocal..CptyClasses CyC WITH(NOLOCK)
	ON		CyC.CptyClasses_Id = Cy.CptyClasses_Id
ORDER BY CompesationGroup ASC

/*
		SELECT __TITLE__ = '=Opciones de ME'
		SELECT __ELEM_TITLE__ = 'ANEXO8BOPTME'+CONVERT(VARCHAR(8),@FECHAEJECUCION,112)
		SELECT __HEADER__     =
		'Grupo de compensacion'
		,'Codigo de operacion'
		,'Cpty_Nombre'
		,'Cpty_Pais'
		,'Cpty_Documento'
		,'Cpty_Codigo SBS'
		,'Vencimiento residual'
		,'Proxima fecha de reprecio'
		,'Rango de vencimiento'
		,'Tasa entregada/recibida'
		,'Moneda entregada/recibida'
		,'Valor razonable'
		,'Tipo de posicion'

		SELECT __FORMAT__=
		NULL
		,NULL
		,NULL
		,NULL
		,NULL
		,NULL
		,'999 999 999'
		,NULL
		,'999 999 999'
		,'-999 999 999.9999'
		,NULL
		,'-999 999 999 999.99'
		,NULL


	/*==============Opciones de M.E.==============*/
SELECT
	'Grupo de compensacion' =
	,'Codigo de operacion' =
/*Contraparte*/
	,'Nombre' =
	,'Pais' =
	,'Documento' =
	,'Codigo SBS' =

	,'Vencimiento residual' =
	,'Subyacente' =
	,'Precio de ejercicio' =
	,'Valor razonable' =
	,'Posicion respecto del subyacente' =
*/

	--LM_KONDORG_14011:Inicio
	--------------------------------------------------------------------
	-- A N E X O (B) : F X O P T I O N S  M. E.  
	--------------------------------------------------------------------
	--Codigo producto
	DECLARE @FxO_KdbTables_Id INT
	SET @FxO_KdbTables_Id = (SELECT TOP 1 KdbTables_Id FROM KplusLocal..KdbTables WITH(NOLOCK) WHERE  KdbTables_Name ='FxOptionsDeals')
	
	--Obtener operaciones FXO
	IF OBJECT_ID('tempdb..#FxOpt_AnexoB') IS NOT NULL
	BEGIN
		DROP TABLE #FxOpt_AnexoB;
	END
	
	CREATE TABLE #FxOpt_AnexoB (
	 [FxOptionsDeals_Id] 			INT
	,[PremiumPayment] 				CHAR(1)
	,[Pairs_Id]						INT
	,[MarketValue]					FLOAT
	,[Codigo_operacion]				VARCHAR(27)
	,[Cpty_Nombre]   				VARCHAR(32)
	,[Cpty_Pais]     				VARCHAR(10)	
	,[Cpty_Documento]				VARCHAR(20)
	,[Cpty_Codigo SBS]				VARCHAR(19)
	,[Vencimiento residual] 		INT
	,[Subyacente]					VARCHAR(7)
	,[Precio Ejercicio]				FLOAT
	,[Valor_Razonable]				FLOAT
	,[Posicion respecto Subyacente]VARCHAR(4)
	);
	
	CREATE INDEX FxOpt_AnexoB_Pairs_Id1	ON #FxOpt_AnexoB (Pairs_Id);
	
	INSERT INTO #FxOpt_AnexoB(
	 [FxOptionsDeals_Id] 			
	,[PremiumPayment] 				
	,[Pairs_Id]						
	,[MarketValue]					
	,[Codigo_operacion]
	,[Cpty_Nombre]
	,[Cpty_Pais]
	,[Cpty_Documento]
	,[Cpty_Codigo SBS]
	,[Vencimiento residual]
	,[Subyacente]
	,[Precio Ejercicio]
	,[Valor_Razonable]
	,[Posicion respecto Subyacente]
	)

SELECT 
 RTK.FxOptionsDeals_FxOptionsDeals_Id
,CASE 
	WHEN RTK.FxOptionsDeals_PremiumPayment = 'Currency 1' THEN '1'
	WHEN RTK.FxOptionsDeals_PremiumPayment = 'Currency 2' THEN '2'
	ELSE '1'
 END AS PremiumPayment
,P.Pairs_Id
,RTK.ValuationData_MarketValue				
,CASE	WHEN RTK.ValuationData_BuyOrSell = 'Buy' AND RTK.ValuationData_CallPut = 'Call'
		THEN 'OPTCC'
		WHEN RTK.ValuationData_BuyOrSell = 'Buy' AND RTK.ValuationData_CallPut = 'Put'
		THEN 'OPTPC'
		WHEN RTK.ValuationData_BuyOrSell = 'Sell' AND RTK.ValuationData_CallPut = 'Call'
		THEN 'OPTCV'
		WHEN RTK.ValuationData_BuyOrSell = 'Sell' AND RTK.ValuationData_CallPut = 'Put'
		THEN 'OPTPV'
END + CONVERT(VARCHAR,RTK.FxOptionsDeals_FxOptionsDeals_Id)
,RTK.ValuationData_CptyName																
,Ci.Cities_ShortName														
,CyPE.Documento																
,ISNULL(CyPE.CodigoSBS,0)													
,DATEDIFF(DAY,@FECHAEJECUCION,TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103))	
,RTK.Pairs_Pairs_ShortName															
,RTK.ValuationData_Strike																	
,NULL																			
,CASE WHEN RTK.ValuationData_BuyOrSell = 'Buy' 
	THEN 'Buy'
	WHEN RTK.ValuationData_BuyOrSell = 'Sell' 
	THEN 'Sell' 
END								

-- VP_KONDORG_14011_202511:Inicio - RTK es ahora la tabla principal
FROM DataKondorPE..TBL_PE_RTK_FX_HIST RTK WITH(NOLOCK)
LEFT JOIN	KplusLocal..Cpty Cy WITH(NOLOCK)
	ON		RTK.ValuationData_CptyShortName = Cy.Cpty_ShortName
LEFT JOIN	KplusLocal..Cities Ci WITH(NOLOCK)
	ON		Cy.Cities_Id = Ci.Cities_Id
LEFT JOIN	Kustom.dbo.TBL_PE_CPTY_CUSTOM	CyPE WITH(NOLOCK)
	ON		Cy.Cpty_Id = CyPE.DealId
INNER JOIN	KplusLocal..Pairs P WITH(NOLOCK)
	ON		RTK.Pairs_Pairs_ShortName = P.Pairs_ShortName
WHERE	RTK.Fecha = @FECHAEJECUCION 
AND		TRY_CONVERT(DATE, RTK.ValuationData_MaturityDate, 103) > @FECHAEJECUCION  
-- VP_KONDORG_14011_202511:Fin
	
	-----------------------------------------------
	--Calcular Valor Razonable
	-----------------------------------------------
	DECLARE @CURRENCIES_B TABLE (Currencies_Id INT PRIMARY KEY)
	
	INSERT INTO @CURRENCIES_B (Currencies_Id)
	SELECT DISTINCT U.Currencies_Id
	FROM (
		SELECT P.Currencies_Id_1, P.Currencies_Id_2
		FROM KplusLocal..Pairs P WITH(NOLOCK)
		INNER JOIN #FxOpt_AnexoB F 
		ON F.Pairs_Id = P.Pairs_Id
	) AS AUX
	UNPIVOT (
		Currencies_Id FOR CurrencyCol IN (Currencies_Id_1, Currencies_Id_2)
	) AS U
	
	DECLARE @EXCHANGE_RATES_TO_PEN_FXO_B TABLE (
		Cur_Id INT PRIMARY KEY,
		TC     FLOAT NULL
	)
	INSERT INTO @EXCHANGE_RATES_TO_PEN_FXO_B (Cur_Id, TC)
	SELECT 
		C.Currencies_Id,
		Kustom.dbo.FUNC_CO_GET_AMOUNT_CCY_DAY(1, C.Currencies_Id, @PEN, @DIAHABIL)
	FROM @CURRENCIES_B C;
	
	
	UPDATE F
	SET [Valor_Razonable] = (F.MarketValue * T.TC)
	FROM #FxOpt_AnexoB F
	INNER JOIN KplusLocal..Pairs P WITH(NOLOCK)
	ON P.Pairs_Id = F.Pairs_Id
	INNER JOIN @EXCHANGE_RATES_TO_PEN_FXO_B T
	ON T.Cur_Id = (CASE WHEN F.PremiumPayment = 1 THEN P.Currencies_Id_1 ELSE P.Currencies_Id_2 END)
		
	--Salida	
	SELECT __TITLE__ = 'Operaciones Opciones con ME'
	SELECT __ELEM_TITLE__ = 'ANEXO8BOPTME'+CONVERT(VARCHAR(8),@FECHAEJECUCION,112)
	SELECT __HEADER__     =	
							'Codigo_operacion'
							,'Cpty Nombre'
							,'Cpty Pais'
							,'Cpty Documento'
							,'Cpty Codigo SBS'
							,'Vencimiento residual'
							,'Subyacente'
							,'Precio Ejercicio'
							,'Valor_Razonable'
							,'Posicion respecto Subyacente'
	
	SELECT __FORMAT__=
							 NULL
							,NULL
							,NULL
							,NULL
							,NULL
							,NULL
							,NULL
							,'99.99'
							,'999 999 999 999 999 999.99'
							,NULL						
	
	
	SELECT 
							 [Codigo_operacion]
							,[Cpty_Nombre]
							,[Cpty_Pais]
							,[Cpty_Documento]
							,[Cpty_Codigo SBS]
							,[Vencimiento residual]
							,[Subyacente]
							,[Precio Ejercicio]
							,[Valor_Razonable]
							,[Posicion respecto Subyacente]
	FROM #FxOpt_AnexoB
	--------------------------------------------------------------------
	-- A N E X O (B) : F X O P T I O N S  M. E.  
	--------------------------------------------------------------------
	--LM_KONDORG_14011:Fin


		SELECT __TITLE__ = 'Swaps de tasas de interes y FRAS'
		SELECT __ELEM_TITLE__ = 'ANEXO8BSWPIR'+CONVERT(VARCHAR(8),@FECHAEJECUCION,112)
		SELECT __HEADER__     =
		'Grupo de compensacion'
		,'Codigo de operacion'
		,'Cpty_Nombre'
		,'Cpty_Pais'
		,'Cpty_Documento'
		,'Cpty_Codigo SBS'
		,'Vencimiento residual'
		,'Proxima fecha de reprecio'
		,'Rango de vencimiento'
		,'Tasa entregada/recibida'
		,'Moneda entregada/recibida'
		,'Valor razonable'
		,'Tipo de posicion'

		SELECT __FORMAT__=
		NULL
		,NULL
		,NULL
		,NULL
		,NULL
		,NULL
		,'999 999 999'
		,NULL
		,'999 999 999'
		,'-999 999 999.9999'
		,NULL
		,'-999 999 999 999.99'
		,NULL
	/*==============Swaps de tasas de interes y FRAS==============*/
SELECT
	'Grupo de compensacion'			= MEFS.CompesationGroup
	,'Codigo de operacion'			= CVSWP.COMPRAVENTASWP
/*Contraparte*/
	,'Nombre'							= ISNULL(Cy.Cpty_Name,'')
	,'Pais'								= ISNULL((SELECT 	Ci.Cities_ShortName
															FROM KplusLocal..Cities Ci WITH(NOLOCK)
															WHERE Cy.Cities_Id = Ci.Cities_Id),'PE')
	,'Documento'						= ISNULL((CASE	WHEN CyPE.Documento IS NOT NULL
																THEN CONVERT(VARCHAR,CyPE.Documento)
																ELSE 'NOSCCATT'
														END),'')
	,'Codigo SBS'						= ISNULL(CyPE.CodigoSBS,0)

	,'Vencimiento residual'			= DATEDIFF(DAY,@FECHAEJECUCION,SWL.MaturityDate)
	,'Proxima fecha de reprecio'	= CONVERT(DATE,ISNULL((CASE	WHEN SWL.Indexation = 'F'
																					THEN SWL.MaturityDate
																					ELSE (SELECT TOP 1 SWS.FixingDate
																							FROM 	KplusLocal..SwapSchedule SWS WITH(NOLOCK)
																							WHERE 	SWS.SwapDeals_Id = SWL.SwapDeals_Id
																							AND		SWS.ScheduleLeg = SWL.LegType
																							AND		DATEDIFF(DAY,SWS.FixingDate,@FECHAEJECUCION) <= 0
																							ORDER BY SWS.FixingDate ASC)
																			END),SWL.MaturityDate))
	,'Rango de vencimiento'			= 1
	,'Tasa entregada/recibida'		= ISNULL(CONVERT(DECIMAL(8,4),(CASE 	WHEN SWL.Indexation = 'F'
																								THEN SWL.FixedRate
																								ELSE (SELECT FRV.Rate
																										FROM	KplusLocal..FloatingRatesValues FRV WITH(NOLOCK)
																										WHERE 	SWL.FloatingRates_Id = FRV.FloatingRates_Id
																										AND		DATEDIFF(DAY,FRV.FRDate,@FECHAEJECUCION) = 0)  +
																									(SWL.AdditiveMargin/100)
																						END)),0)/100
	,'Moneda entregada/recibida'	= CU.Currencies_ShortName
	,'Valor razonable'				= (CASE	WHEN CU.Currencies_ShortName = 'USD'
														THEN
														CONVERT(DECIMAL(18,2),CONVERT(DECIMAL(18,2),ISNULL( (SELECT 	SUM(RawPLData_Npv)
																						FROM 	DataKondorPE..TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
																						WHERE	SwapDeals_SwapDeals_Id = MEFS.Deal_Id
																						AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0),0)) * (SELECT Kustom.dbo.FUNC_PE_GET_AMOUNT_CCY_DAY(1, CU.Currencies_Id, @PEN, @FECHAEJECUCION)))
														ELSE
														CONVERT(DECIMAL(18,2),CONVERT(DECIMAL(18,2),ISNULL( (SELECT 	SUM(RawPLData_Npv)
																						FROM 	DataKondorPE..TBL_PE_RTK_SWP_HIST WITH(NOLOCK)
																						WHERE	SwapDeals_SwapDeals_Id = MEFS.Deal_Id
																						AND		DATEDIFF(DAY,Fecha,@FECHAEJECUCION) = 0),0)))
												END)
	,'Tipo de posicion'				= MEFS.PositionType
FROM	DataKondorPE.dbo.TBL_PE_MOTOR_EMPAREJAMIENTO_FWD_SWP MEFS WITH(NOLOCK)
INNER JOIN @COMPRAVENTASWP CVSWP
	ON		CVSWP.SwapDeals_Id = MEFS.Deal_Id
INNER JOIN KplusLocal..SwapLeg SWL WITH(NOLOCK)
	ON		SWL.SwapDeals_Id = MEFS.Deal_Id
	AND	SWL.LegType = (CASE 	WHEN MEFS.PositionType = 'LARGA'
										THEN 'L'
										ELSE 'D'
								END)
INNER JOIN KplusLocal..Cpty Cy WITH(NOLOCK)
	ON		Cy.Cpty_Id = SWL.Cpty_Id
INNER JOIN KplusLocal..Currencies CU WITH(NOLOCK)
	ON		CU.Currencies_Id = (SELECT Kustom.dbo.FUNC_DRV_SWAP_CUR_PPAL_LEG(SWL.SwapDeals_Id,SWL.LegType))
	AND	DATEDIFF(DAY,MEFS.Fecha,@FECHAEJECUCION) = 0
	AND	InstrumentType	= 'SwapDeals'
	AND	InstrumentName NOT IN ('CCS','SC')
	AND	CompesationGroup <> 0
LEFT JOIN Kustom.dbo.TBL_PE_CPTY_CUSTOM	CyPE WITH(NOLOCK)
	ON		Cy.Cpty_Id = CyPE.DealId
LEFT JOIN KplusLocal..CptyClasses CyC WITH(NOLOCK)
	ON		CyC.CptyClasses_Id = Cy.CptyClasses_Id
ORDER BY CompesationGroup ASC

END

END
GO
GRANT EXECUTE ON Kustom.dbo.PRC_PE_DRV_ANEXO08 TO PUBLIC  
GO
PRINT '<<<<< END CREATING Stored Procedure - "Kustom.dbo.PRC_PE_DRV_ANEXO08" >>>>>'