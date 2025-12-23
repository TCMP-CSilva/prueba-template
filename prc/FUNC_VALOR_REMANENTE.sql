USE [Kustom]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_WARNINGS ON
GO
 
PRINT '<<<<< START CREATING FUNCTION - FUNC_VALOR_REMANENTE >>>>>' 
IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('[FUNC_VALOR_REMANENTE]') AND type = 'FN')
BEGIN
PRINT '<<<<< DROP FUNCTION - FUNC_VALOR_REMANENTE >>>>>'
	  DROP FUNCTION dbo.FUNC_VALOR_REMANENTE;
END
GO
 
CREATE  FUNCTION [dbo].FUNC_VALOR_REMANENTE	(@DealId			INT, 
											@FechaPago			DATE,
											@Pata				VARCHAR(1))
RETURNS FLOAT
 
AS
BEGIN

/*
*******************************************************************************************************
DESCRIPCION	:	Funcion que trae el valor remanente del valor de los flujos KG-15722.
AUTOR		:	Cindy Calderon
FECHA		:	2025-12-19
EMPRESA		:	TCMP
EJECUCION	:	SELECT Kustom.dbo.FUNC_VALOR_REMANENTE(@DealId,@FechaPago,@Pata)
			:	SELECT Kustom.dbo.FUNC_VALOR_REMANENTE(50424,'2025-08-29','D')
NOTA		:	Se excluyen los acentos dentro de este documento. 
*******************************************************************************************************
CONTROL DE CAMBIOS
*******************************************************************************************************
DESCRIPCION	:	
AUTOR		:	
FECHA		:	
EMPRESA		:	
*******************************************************************************************************
DESCRIPCION	:	
AUTOR		:	
FECHA		:	
EMPRESA		:	
*******************************************************************************************************
*/

DECLARE			@SwapDeals					INT			=	(SELECT KdbTables_Id FROM kplustp..KdbTables WITH (NOLOCK) WHERE KdbTables_Name = 'SwapDeals'),
				@Resultado					FLOAT	 			



DECLARE			@DatosBase Table (
				Principal					FLOAT,
				PrincipalCur1				FLOAT,
				PaymentDate					DATE,
				Lagg						FLOAT,
				Lagg2						FLOAT)
 
INSERT INTO		@DatosBase
SELECT DISTINCT	sh.Principal,
				sh.PrincipalCur1,
				sh.PaymentDate,
				Principal,
				PrincipalCur1

FROM			kplustp..Event				e   WITH (NOLOCK)
INNER JOIN		kplustp..BODealFOKey		bo  WITH (NOLOCK)
ON				e.BODeal_Id					=	bo.BODeal_Id
AND				bo.DealIdFO					=	@DealId 
AND				KdbTables_Id				=	@SwapDeals
INNER JOIN		kplustp..EventCashFlowData	sh WITH (NOLOCK)
ON				e.Event_Id					=	sh.Event_Id
AND				CashFlowType				=	'I'
AND				ScheduleLeg					=	@Pata
ORDER BY		PaymentDate asc 



SELECT Top 1	@Resultado					=	(CASE WHEN Lagg2 = 0
														THEN Lagg
														ELSE Lagg2
														END)
FROM			@DatosBase 
WHERE			PaymentDate					> @FechaPago
ORDER BY		PaymentDate
			

RETURN  @Resultado
 
END
GO
PRINT '<<<<< EXECUTE GRANT Function - FUNC_VALOR_REMANENTE >>>>>'
GO
GRANT EXECUTE ON Kustom.dbo.FUNC_VALOR_REMANENTE TO PUBLIC
GO
PRINT '<<<<< END CREATING Function - FUNC_VALOR_REMANENTE >>>>'
GO


