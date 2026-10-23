
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

def create_employee_dummy_data(connection, num_records):
  try:
    with connection.cursor() as cursor:
      print(f"Generating and inserting {num_records} dummy records into the employee table...")

      for i in range(num_records):
        first_name = fake.first_name()
        last_name = fake.last_name()
        full_name = f"{first_name} {last_name}"
        
        # Append an index to ensure email uniqueness and avoid duplicate entry errors
        email = f"emp_{i}_{fake.unique.email()}"
        phone = fake.phone_number()
        
        job_title = fake.job()
        departments = ["Engineering", "Marketing", "Sales", "HR", "Finance", "Product"]
        department = random.choice(departments)
        
        # Assign a random manager ID or None for the first few records
        manager_id = random.choice([None, random.randint(1, 10)]) if i > 0 else None
        
        # Generate a random hire date within the past 5 years (1825 days)
        random_days = random.randint(0, 1825)
        random_seconds = random.randint(0, 86400)
        hired_on = datetime.now() - timedelta(days=random_days, seconds=random_seconds)
        
        is_active = random.choice([True, False])
        
        created_at = datetime.now() - timedelta(days=random.randint(0, 30), seconds=random.randint(0, 86400))
        updated_at = datetime.now()

        sql = """
            INSERT INTO employee (
                first_name, last_name, full_name, email, phone, 
                job_title, department, manager_id, hired_on, 
                is_active, created_at, updated_at
            ) 
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """
        cursor.execute(sql, (
            first_name, last_name, full_name, email, phone,
            job_title, department, manager_id, hired_on,
            is_active, created_at, updated_at
        ))

      connection.commit()
      print("Employee dummy data successfully inserted!")

  except Exception as e:
    print(f"An error occurred: {e}")
    connection.rollback()

def create_customer_dummy_data(connection, num_records):
  try:
    with connection.cursor() as cursor:
      print(f"Generating and inserting {num_records} dummy records into the customer table...")

      for i in range(num_records):
        first_name = fake.first_name()
        last_name = fake.last_name()
        full_name = f"{first_name} {last_name}"
        
        # Append an index to ensure email uniqueness and avoid duplicate entry errors
        email = f"cust_{i}_{fake.unique.email()}"
        phone = fake.phone_number()
        
        tiers = ["Standard", "Silver", "Gold", "Platinum"]
        tier = random.choice(tiers)
        
        # Assign a random account manager ID or None for the first few records
        account_manager_id = random.choice([None, random.randint(1, 10)]) if i > 0 else None
        
        # Generate a random sign-up date within the past 3 years (1095 days)
        random_days = random.randint(0, 1095)
        random_seconds = random.randint(0, 86400)
        signed_up_on = datetime.now() - timedelta(days=random_days, seconds=random_seconds)
        
        is_active = random.choice([True, False])
        
        created_at = datetime.now() - timedelta(days=random.randint(0, 30), seconds=random.randint(0, 86400))
        updated_at = datetime.now()

        sql = """
            INSERT INTO customer (
                first_name, last_name, full_name, email, phone, 
                tier, account_manager_id, signed_up_on, 
                is_active, created_at, updated_at
            ) 
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """
        cursor.execute(sql, (
            first_name, last_name, full_name, email, phone,
            tier, account_manager_id, signed_up_on,
            is_active, created_at, updated_at
        ))

      connection.commit()
      print("Customer dummy data successfully inserted!")

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
