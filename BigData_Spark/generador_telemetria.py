import pandas as pd
import random
from faker import Faker
from datetime import datetime, timedelta

fake = Faker()

# Configuración del volumen de datos (1 millón para la prueba inicial)
NUM_REGISTROS = 1000

print(f"Generando {NUM_REGISTROS} registros de telemetría...")

data = []
fecha_inicio = datetime(2026, 9, 1)

for i in range(NUM_REGISTROS):
    # Simulamos datos para los 8 volquetes y 8 conductores de su BD
    id_volquete = random.randint(1, 8)
    id_conductor = random.randint(1, 8)
    
    # Incrementamos el tiempo aleatoriamente para simular pings del sensor
    fecha_inicio += timedelta(minutes=random.randint(1, 5))
    
    # Simulamos el estado del motor
    estado = random.choice(['En movimiento', 'Detenido_Motor_Encendido', 'Apagado'])
    rpm = 0 if estado == 'Apagado' else random.randint(800, 2500)

    data.append([i+1, id_volquete, id_conductor, fecha_inicio, rpm, estado])

# Convertir a DataFrame
df = pd.DataFrame(data, columns=['id_telemetria', 'id_volquete', 'id_conductor', 'fecha_hora', 'rpm_motor', 'estado'])

# 1. Exportar para SQL Server (CSV)
df.to_csv('telemetria_luchito.csv', index=False)
print("Archivo CSV generado exitosamente.")

# 2. Exportar para Apache Spark (Parquet particionado)
# Parquet es el formato ideal para Big Data por su compresión columnar
df.to_parquet('telemetria_luchito.parquet', engine='pyarrow')
print("Archivo Parquet generado exitosamente.")