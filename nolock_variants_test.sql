-- nolock_variants_test.sql

-- ✅ Caso 1: WITH (NOLOCK) en mayúsculas
SELECT * FROM dbo.Empleados WITH (NOLOCK);

-- ✅ Caso 2: with (nolock) en minúsculas
SELECT * FROM dbo.Empleados with (nolock);

-- ✅ Caso 3: With (NoLock) mezcla de mayúsculas y minúsculas
SELECT * FROM dbo.Empleados With (NoLock);

-- ✅ Caso 4: WITH(NOLOCK) sin espacio
SELECT * FROM dbo.Empleados WITH(NOLOCK);

-- ✅ Caso 5: (NOLOCK) solo paréntesis, sin WITH
SELECT * FROM dbo.Empleados (NOLOCK);

-- ✅ Caso 6: (nolock) minúsculas sin WITH
SELECT * FROM dbo.Empleados (nolock);

-- ✅ Caso 7: WITH (NOLOCK, READUNCOMMITTED)
SELECT * FROM dbo.Empleados WITH (NOLOCK, READUNCOMMITTED);

-- ✅ Caso 8: with(nolock, readuncommitted)
SELECT * FROM dbo.Empleados with(nolock, readuncommitted);

-- ❌ Caso 9: Falta hint
SELECT * FROM dbo.Clientes WITH (NOLOCK);

-- ❌ Caso 10: JOIN sin NOLOCK en ninguna tabla
SELECT a.Id, b.Total
FROM dbo.Ordenes a WITH (NOLOCK)
JOIN dbo.DetalleVentas b WITH (NOLOCK); ON a.Id = b.VentaID;

-- ❌ Caso 11: JOIN con NOLOCK en solo una tabla
SELECT a.Id, b.Cantidad
FROM dbo.Ventas a WITH (NOLOCK)
JOIN dbo.DetalleVentas b WITH (NOLOCK) ON a.Id = b.VentaID;

-- ✅ Caso 12: JOIN con NOLOCK en ambas tablas
SELECT a.Id, b.Cantidad
FROM dbo.Ventas a (NOLOCK)
JOIN dbo.DetalleVentas b WITH(NOLOCK) ON a.Id = b.VentaID;

-- ✅ Caso 13: Tabla temporal debe ser ignorada
SELECT * FROM #TempTable;

-- ✅ Caso 14: Tabla dinámica con @ debe ser ignorada
SELECT * FROM @TablaDinamica;

-- ✅ Caso 15: JOIN de tablas dinámicas también debe ser ignorado
SELECT * 
FROM @Temp1 t1
JOIN @Temp2 t2 ON t1.id = t2.id;

-- ✅ Caso 16: Alias en tabla y hint correcto
SELECT * FROM dbo.Facturas f with(nolock);

-- ✅ Caso adicional: With (NoLock) mezcla de mayúsculas y minúsculas
SELECT * FROM dbo.Empleados With (NoLock);



-- Fin del archivo - ultimo cambio
