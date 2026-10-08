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