
# pip install pymysql faker

from datetime import datetime, timedelta
import random
from faker import Faker
import pymysql

# Initialize Faker with US English locale to generate American-style dummy data.
fake = Faker("en_US")

# MySQL database connection settings
db_connection = pymysql.connect(
    host="localhost",
    user="root",  # Replace with your DB username
    password="your_password",  # Replace with your DB password
    database="your_db",  # Replace with your DB name
    charset="utf8mb4",
    cursorclass=pymysql.cursors.DictCursor,
)

try:
  with db_connection.cursor() as cursor:
    # Specify the number of dummy records to generate
    num_records = 50
    print(
        f"Generating and inserting {num_records} dummy records into the customer"
        " table..."
    )

    for i in range(num_records):
      name = fake.name()
      # Append an index to ensure email uniqueness and avoid duplicate entry errors
      email = f"user_{i}_{fake.unique.email()}"
      phone = fake.phone_number()

      # Generate a random datetime within the past 1 year (365 days)
      random_days = random.randint(0, 365)
      random_seconds = random.randint(0, 86400)  # Total seconds in a day
      created_at = datetime.now() - timedelta(
          days=random_days, seconds=random_seconds
      )

      # Insert including the random created_at time
      sql = """
                INSERT INTO customer (name, email, phone, created_at) 
                VALUES (%s, %s, %s, %s)
            """
      cursor.execute(sql, (name, email, phone, created_at))

    # Commit changes to the database
    db_connection.commit()
    print("Dummy data successfully inserted!")

except Exception as e:
  print(f"An error occurred: {e}")
  db_connection.rollback()

finally:
  db_connection.close()