
# pip install pymysql faker

from datetime import datetime, timedelta
import random
from faker import Faker
import pymysql

# Initialize Faker with US English locale to generate American-style dummy data.
fake = Faker("en_US")

num_records = 50

# mysql localhost database connection
def connect_db():
  db_connection = pymysql.connect(
      host="localhost",
      user="root",  # Replace with your DB username
      password="mysql123",  # Replace with your DB password
      database="shop_db",  # Replace with your DB name
      charset="utf8mb4",
      cursorclass=pymysql.cursors.DictCursor,
  )
  return db_connection

def create_customer_dummy_data(connection, num_records):
  try:
    with connection.cursor() as cursor:
      print(f"Generating and inserting {num_records} dummy records into the customer table...")

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
      connection.commit()
      print("Dummy data successfully inserted!")

  except Exception as e:
    print(f"An error occurred: {e}")
    connection.rollback()

def create_product_dummy_data(connection, num_records):
  try:
    with connection.cursor() as cursor:
      print(f"Generating and inserting {num_records} dummy records into the product table...")

      for i in range(num_records):
        name = fake.word()
        price = fake.random_int(min=1000, max=100000)
        stock = fake.random_int(min=0, max=500)
        
        random_days = random.randint(0, 365)
        random_seconds = random.randint(0, 86400)
        created_at = datetime.now() - timedelta(
            days=random_days, seconds=random_seconds
        )

        sql = """
                  INSERT INTO product (name, price, stock, created_at) 
                  VALUES (%s, %s, %s, %s)
              """
        cursor.execute(sql, (name, price, stock, created_at))

      connection.commit()
      print("Dummy data successfully inserted!")

  except Exception as e:
    print(f"An error occurred: {e}")
    connection.rollback()

def create_order_dummy_data(connection, num_records):
  try:
    with connection.cursor() as cursor:
      cursor.execute("SELECT customer_id FROM customer")
      customer_ids = [row["customer_id"] for row in cursor.fetchall()]

      cursor.execute("SELECT product_id, price FROM product")
      products = [
          (row["product_id"], row["price"]) for row in cursor.fetchall()
      ]
      
      print(f"Generating and inserting {num_records} dummy records into the order table...")

      for i in range(num_records):
        customer_id = random.choice(customer_ids)
        product_id, price = random.choice(products)
        quantity = fake.random_int(min=1, max=10)
        total_price = price * quantity
        order_date = fake.date_time_between(
            start_date="-1y",
            end_date="now"
        )

        sql = """
                  INSERT INTO `order` (customer_id, product_id, quantity, total_price, order_date) 
                  VALUES (%s, %s, %s, %s, %s)
              """
        cursor.execute(sql, (customer_id, product_id, quantity, total_price, order_date))

      connection.commit()
      print("Dummy data successfully inserted!")

  except Exception as e:
    print(f"An error occurred: {e}")
    connection.rollback()

if __name__ == "__main__":
  db_connection = connect_db()
  
  try:
    # create_customer_dummy_data(db_connection, num_records)
    # create_product_dummy_data(db_connection, num_records)
    create_order_dummy_data(db_connection, num_records)
  finally:
    db_connection.close()
    print("Database connection closed.")
