CREATE TABLE Telemetria_Staging (
    id_telemetria INT PRIMARY KEY,
    id_volquete INT,
    id_conductor INT,
    fecha_hora DATETIME,
    rpm_motor INT,
    estado VARCHAR(50)
);
GO

-- 2. Cargar el millón de registros desde el CSV 
BULK INSERT Telemetria_Staging
FROM 'C:\Users\jonat\AppData\Local\Programs\Microsoft VS Code\telemetria_luchito.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2
);
GO

-- Proceso de limpieza de datos (ETL)
USE TransportesLuchito; 
GO

UPDATE Registro_Horas_Motor
SET estado_validacion = 'observado',
    observaciones = 'Error temporal: hora de fin es anterior al inicio'
WHERE hora_fin <= hora_inicio;

SELECT * FROM Registro_Horas_Motor;

--Script para medir tiempo que toma al SQL sumar minutos reales trabajados por volquete
DBCC DROPCLEANBUFFERS;
DECLARE @StartTime DATETIME2 = SYSDATETIME();

SELECT 
    t.id_volquete,
    v.placa,
    t.id_conductor,
    c.nombres,
    c.apellidos,
    COUNT(*) AS minutos_totales_encendido
FROM Telemetria_Staging t
INNER JOIN Volquete v ON t.id_volquete = v.id_volquete
INNER JOIN Conductor c ON t.id_conductor = c.id_conductor
WHERE t.estado IN ('En movimiento', 'Detenido_Motor_Encendido')
GROUP BY t.id_volquete, v.placa, t.id_conductor, c.nombres, c.apellidos
ORDER BY minutos_totales_encendido DESC;

DECLARE @EndTime DATETIME2 = SYSDATETIME();
SELECT DATEDIFF(millisecond, @StartTime, @EndTime) AS Latencia_SQL_ms;


-- Limpiar caché para prueba real (Evitar ventajas en memoria)
DBCC DROPCLEANBUFFERS;
GO

-- Activar el cronómetro interno de SQL Server
SET STATISTICS TIME ON;
GO

-- Consulta de validación (Simulación)
SELECT v.placa, c.nombres, COUNT(t.id_telemetria) as total_pings
FROM Telemetria_Staging t
INNER JOIN Volquete v ON t.id_volquete = v.id_volquete
INNER JOIN Conductor c ON t.id_conductor = c.id_conductor
GROUP BY v.placa, c.nombres;
GO

SET STATISTICS TIME OFF;


--Revisar Completitud (Nulos):
SELECT COUNT(*) AS Registros_Incompletos 
FROM Registro_Horas_Motor 
WHERE hora_fin IS NULL OR hora_inicio IS NULL;


SELECT COUNT(*) AS Registros_Inconsistentes
FROM Registro_Horas_Motor 
WHERE hora_fin <= hora_inicio 
   OR DATEDIFF(MINUTE, hora_inicio, hora_fin) / 60.0 > 24;

SELECT COUNT(*) AS Total_Registros_Procesados 
FROM TransportesLuchito.dbo.Registro_Horas_Motor;

--FLUJO ETL


-- 1. Crear Dimensiones
CREATE TABLE Dim_Volquete (
    id_volquete INT PRIMARY KEY,
    codigo_unidad VARCHAR(10),
    placa VARCHAR(10),
    marca VARCHAR(30),
    modelo VARCHAR(30),
    anio_fabricacion INT,
    capacidad_carga DECIMAL(8,2),
    estado VARCHAR(15)
);

CREATE TABLE Dim_Conductor (
    id_conductor INT PRIMARY KEY,
    dni VARCHAR(8),
    nombres VARCHAR(50),
    apellidos VARCHAR(50),
    licencia_conducir VARCHAR(15),
    categoria_licencia VARCHAR(5),
    estado VARCHAR(15)
);

CREATE TABLE Dim_ClienteFrente (
    id_frente INT PRIMARY KEY,
    nombre_cliente VARCHAR(100),
    nombre_frente VARCHAR(50),
    ubicacion VARCHAR(100),
    estado VARCHAR(15)
);

CREATE TABLE Dim_Tiempo (
    id_tiempo INT PRIMARY KEY IDENTITY(1,1),
    fecha DATE UNIQUE NOT NULL,
    anio INT,
    mes INT,
    dia INT,
    nombre_mes VARCHAR(20)
);

-- 2. Crear Tablas de Hechos
CREATE TABLE Fact_HorasMotor (
    id_hecho INT PRIMARY KEY IDENTITY(1,1),
    id_tiempo INT FOREIGN KEY REFERENCES Dim_Tiempo(id_tiempo),
    id_volquete INT FOREIGN KEY REFERENCES Dim_Volquete(id_volquete),
    id_conductor INT FOREIGN KEY REFERENCES Dim_Conductor(id_conductor),
    id_frente INT FOREIGN KEY REFERENCES Dim_ClienteFrente(id_frente),
    hora_inicio TIME,
    hora_fin TIME,
    horas_trabajadas DECIMAL(5,2),
    flag_validado INT
);

CREATE TABLE Fact_Telemetria (
    id_hecho_telemetria BIGINT PRIMARY KEY IDENTITY(1,1),
    id_tiempo INT FOREIGN KEY REFERENCES Dim_Tiempo(id_tiempo),
    id_volquete INT FOREIGN KEY REFERENCES Dim_Volquete(id_volquete),
    id_conductor INT FOREIGN KEY REFERENCES Dim_Conductor(id_conductor),
    hora_registro TIME,
    rpm_motor INT,
    estado_sensor VARCHAR(50)
);

DECLARE @FechaInicio DATE = '2026-01-01';
DECLARE @FechaFin DATE = '2026-12-31';

WHILE @FechaInicio <= @FechaFin
BEGIN
    INSERT INTO Dim_Tiempo (fecha, anio, mes, dia, nombre_mes)
    VALUES (
        @FechaInicio, YEAR(@FechaInicio), MONTH(@FechaInicio), DAY(@FechaInicio), DATENAME(MONTH, @FechaInicio)
    );
    SET @FechaInicio = DATEADD(DAY, 1, @FechaInicio);
END;

SET STATISTICS TIME ON;
SET STATISTICS IO ON;

-- 1. Cargar Dimensiones
INSERT INTO Dim_Volquete (id_volquete, codigo_unidad, placa, marca, modelo, anio_fabricacion, capacidad_carga, estado)
SELECT v.id_volquete, v.codigo_unidad, UPPER(REPLACE(v.placa,'-','')), v.marca, v.modelo, v.anio_fabricacion, v.capacidad_carga, v.estado
FROM Volquete v  
WHERE NOT EXISTS (SELECT 1 FROM Dim_Volquete dv WHERE dv.id_volquete = v.id_volquete);

INSERT INTO Dim_Conductor (id_conductor, dni, nombres, apellidos, licencia_conducir, categoria_licencia, estado)
SELECT c.id_conductor, c.dni, c.nombres, c.apellidos, c.licencia_conducir, c.categoria_licencia, c.estado
FROM Conductor c 
WHERE NOT EXISTS (SELECT 1 FROM Dim_Conductor dc WHERE dc.id_conductor = c.id_conductor);

INSERT INTO Dim_ClienteFrente (id_frente, nombre_cliente, nombre_frente, ubicacion, estado)
SELECT f.id_frente, f.nombre_cliente, f.nombre_frente, f.ubicacion, f.estado
FROM Cliente_Frente f 
WHERE NOT EXISTS (SELECT 1 FROM Dim_ClienteFrente df WHERE df.id_frente = f.id_frente);

-- 2. Cargar Tabla de Hechos (El filtro de calidad)
INSERT INTO Fact_HorasMotor (id_tiempo, id_volquete, id_conductor, id_frente, hora_inicio, hora_fin, horas_trabajadas, flag_validado)
SELECT 
    t.id_tiempo, r.id_volquete, r.id_conductor, r.id_frente, r.hora_inicio, r.hora_fin, r.horas_trabajadas, 1
FROM (
    SELECT id_volquete, id_conductor, id_frente, fecha, hora_inicio, hora_fin, horas_trabajadas,
        CASE 
            WHEN hora_fin <= hora_inicio THEN 'observado'
            WHEN DATEDIFF(MINUTE, hora_inicio, hora_fin) / 60.0 > 24 THEN 'observado'
            WHEN ABS(horas_trabajadas - (DATEDIFF(MINUTE, hora_inicio, hora_fin) / 60.0)) > 0.25 THEN 'observado'
            ELSE estado_validacion 
        END AS estado_final
    FROM Registro_Horas_Motor
    WHERE fecha IS NOT NULL AND hora_fin IS NOT NULL
) r
INNER JOIN Dim_Tiempo t ON t.fecha = r.fecha
WHERE r.estado_final = 'validado';


DECLARE @FechaInicio DATE = '2026-01-01';
DECLARE @FechaFin DATE = '2026-12-31';

WHILE @FechaInicio <= @FechaFin
BEGIN
    -- Verifica si la fecha NO existe antes de insertarla
    IF NOT EXISTS (SELECT 1 FROM Dim_Tiempo WHERE fecha = @FechaInicio)
    BEGIN
        INSERT INTO Dim_Tiempo (fecha, anio, mes, dia, nombre_mes)
        VALUES (
            @FechaInicio, YEAR(@FechaInicio), MONTH(@FechaInicio), DAY(@FechaInicio), DATENAME(MONTH, @FechaInicio)
        );
    END
    SET @FechaInicio = DATEADD(DAY, 1, @FechaInicio);
END;




-------------------------------------------------------------------
-- CONFIGURACIÓN DE MÉTRICAS (Para el Capítulo VI)
-------------------------------------------------------------------
SET STATISTICS TIME ON;
SET STATISTICS IO ON;
PRINT 'Iniciando proceso ETL...';

-------------------------------------------------------------------
-- FASE 1: CARGA DE DIMENSIONES (ETL de Catálogos)
-------------------------------------------------------------------
-- 1.1 Dimensión Volquete (Limpiando caracteres de la placa)
INSERT INTO Dim_Volquete (id_volquete, codigo_unidad, placa, marca, modelo, anio_fabricacion, capacidad_carga, estado)
SELECT 
    v.id_volquete, 
    v.codigo_unidad, 
    UPPER(REPLACE(v.placa,'-','')), -- Transformación: Placa limpia
    v.marca, 
    v.modelo, 
    v.anio_fabricacion, 
    v.capacidad_carga, 
    v.estado
FROM Volquete v  
WHERE NOT EXISTS (SELECT 1 FROM Dim_Volquete dv WHERE dv.id_volquete = v.id_volquete);

-- 1.2 Dimensión Conductor
INSERT INTO Dim_Conductor (id_conductor, dni, nombres, apellidos, licencia_conducir, categoria_licencia, estado)
SELECT 
    c.id_conductor, c.dni, c.nombres, c.apellidos, c.licencia_conducir, c.categoria_licencia, c.estado
FROM Conductor c 
WHERE NOT EXISTS (SELECT 1 FROM Dim_Conductor dc WHERE dc.id_conductor = c.id_conductor);

-- 1.3 Dimensión Cliente / Frente de Trabajo
INSERT INTO Dim_ClienteFrente (id_frente, nombre_cliente, nombre_frente, ubicacion, estado)
SELECT 
    f.id_frente, f.nombre_cliente, f.nombre_frente, f.ubicacion, f.estado
FROM Cliente_Frente f 
WHERE NOT EXISTS (SELECT 1 FROM Dim_ClienteFrente df WHERE df.id_frente = f.id_frente);

-------------------------------------------------------------------
-- FASE 2: CARGA DE DIMENSIÓN TIEMPO (Generación Segura)
-------------------------------------------------------------------
-- Genera el calendario de 2026 sin romper reglas UNIQUE
DECLARE @FechaInicio DATE = '2026-01-01';
DECLARE @FechaFin DATE = '2026-12-31';

WHILE @FechaInicio <= @FechaFin
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Dim_Tiempo WHERE fecha = @FechaInicio)
    BEGIN
        INSERT INTO Dim_Tiempo (fecha, anio, mes, dia, nombre_mes)
        VALUES (
            @FechaInicio, YEAR(@FechaInicio), MONTH(@FechaInicio), DAY(@FechaInicio), DATENAME(MONTH, @FechaInicio)
        );
    END
    SET @FechaInicio = DATEADD(DAY, 1, @FechaInicio);
END;

-------------------------------------------------------------------
-- FASE 3: CARGA DE TABLA DE HECHOS OPERATIVOS (Horas Motor)
-------------------------------------------------------------------
-- Aquí se aplica la lógica de calidad y transformación profunda
INSERT INTO Fact_HorasMotor (id_tiempo, id_volquete, id_conductor, id_frente, hora_inicio, hora_fin, horas_trabajadas, flag_validado)
SELECT 
    t.id_tiempo, 
    r.id_volquete, 
    r.id_conductor, 
    r.id_frente, 
    r.hora_inicio, 
    r.hora_fin, 
    r.horas_trabajadas, 
    1 AS flag_validado
FROM (
    SELECT 
        id_volquete, id_conductor, id_frente, fecha, hora_inicio, hora_fin, horas_trabajadas,
        -- Reglas de validación (Transformación)
        CASE 
            WHEN hora_fin <= hora_inicio THEN 'observado'
            WHEN DATEDIFF(MINUTE, hora_inicio, hora_fin) / 60.0 > 24 THEN 'observado'
            WHEN ABS(horas_trabajadas - (DATEDIFF(MINUTE, hora_inicio, hora_fin) / 60.0)) > 0.25 THEN 'observado'
            ELSE estado_validacion 
        END AS estado_final
    FROM Registro_Horas_Motor
    WHERE fecha IS NOT NULL AND hora_fin IS NOT NULL
) r
INNER JOIN Dim_Tiempo t ON t.fecha = r.fecha
-- Carga restrictiva: Solo ingresan los datos que superaron los filtros de calidad
WHERE r.estado_final = 'validado';

-------------------------------------------------------------------
-- FASE 4: CARGA DE TABLA DE HECHOS BIG DATA (Telemetría)
-------------------------------------------------------------------
-- Ingesta de la tabla de staging hacia el modelo dimensional
INSERT INTO Fact_Telemetria (id_tiempo, id_volquete, id_conductor, hora_registro, rpm_motor, estado_sensor)
SELECT 
    dt.id_tiempo,
    ts.id_volquete,
    ts.id_conductor,
    CAST(ts.fecha_hora AS TIME) AS hora_registro, -- Transformación: Separa la hora
    ts.rpm_motor,
    ts.estado
FROM Telemetria_Staging ts
INNER JOIN Dim_Tiempo dt ON dt.fecha = CAST(ts.fecha_hora AS DATE) -- Transformación: Separa la fecha para unir al calendario
-- Filtro de calidad: Elimina falsos positivos del sensor de motor
WHERE ts.rpm_motor >= 0;

PRINT 'Proceso ETL completado exitosamente.';