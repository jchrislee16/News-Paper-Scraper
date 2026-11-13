from datetime import datetime, timedelta
import random
from faker import Faker
import pymysql

fake = Faker("en_US")

def connect_db():
    db_connection = pymysql.connect(
        host="localhost",
        user="root",
        password="mysql123",
        database="shop_db",
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
    )
    return db_connection

def create_employee_table():
    connection = connect_db()

    drop_sql = "DROP TABLE IF EXISTS employee;"

    create_sql = """
    CREATE TABLE IF NOT EXISTS employee (
        employee_id INT AUTO_INCREMENT PRIMARY KEY,
        first_name VARCHAR(50) NOT NULL,
        last_name VARCHAR(50) NOT NULL,
        full_name VARCHAR(101) NOT NULL,
        email VARCHAR(100) UNIQUE NOT NULL,
        phone VARCHAR(50),
        job_title VARCHAR(100),
        department VARCHAR(50),
        manager_id INT,
        hired_on DATETIME,
        is_active BOOLEAN,
        created_at DATETIME,
        updated_at DATETIME
    );
    """
    
    try:
        with connection.cursor() as cursor:
            cursor.execute(drop_sql)
            cursor.execute(create_sql)
        connection.commit()
        print("The employee table has been successfully created or already exists.")
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        connection.close()
        
def create_employee_dummy_data(cursor):
    first_name = fake.first_name()
    last_name = fake.last_name()
    full_name = f"{first_name} {last_name}"
    email = fake.unique.email()
    phone = fake.phone_number()
    job_title = fake.job()
    department = random.choice(["Engineering", "Marketing", "Sales", "HR", "Finance", "Product"])
    manager_id = random.choice([None, random.randint(1, 10)])
    hired_on = datetime.now() - timedelta(days=random.randint(0, 1825), seconds=random.randint(0, 86400))
    is_active = random.choice([True, False])
    created_at = datetime.now() - timedelta(days=random.randint(0, 30))
    updated_at = datetime.now()

    sql = """
        INSERT INTO employee (
            first_name, last_name, full_name, email, phone, 
            job_title, department, manager_id, hired_on, 
            is_active, created_at, updated_at
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    cursor.execute(sql, (
        first_name, last_name, full_name, email, phone,
        job_title, department, manager_id, hired_on,
        is_active, created_at, updated_at
    ))

def create_customer_dummy_data(cursor, num_records):
    first_name = fake.first_name()
    last_name = fake.last_name()
    full_name = f"{first_name} {last_name}"
    email = fake.unique.email()
    phone = fake.phone_number()
    tier = random.choice(["Bronze", "Silver", "Gold", "Platinum"])
    account_manager_id = random.choice([None, random.randint(1, num_records)])
    signed_up_on = datetime.now() - timedelta(days=random.randint(0, 1000))
    is_active = random.choice([True, False])
    created_at = datetime.now() - timedelta(days=random.randint(0, 30))
    updated_at = datetime.now()

    sql = """
        INSERT INTO customer (
            first_name, last_name, full_name, email, phone, 
            tier, account_manager_id, signed_up_on, 
            is_active, created_at, updated_at
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    cursor.execute(sql, (
        first_name, last_name, full_name, email, phone,
        tier, account_manager_id, signed_up_on,
        is_active, created_at, updated_at
    ))

def create_product_category_dummy_data(cursor):
    cursor.execute("INSERT INTO product_category (name, parent_category_id, description) VALUES ('Electronics', NULL, %s), ('Clothing', NULL, %s), ('Home & Garden', NULL, %s), ('Books', NULL, %s), ('Sports', NULL, %s)", 
                   (fake.sentence(), fake.sentence(), fake.sentence(), fake.sentence(), fake.sentence()))
    
    cursor.connection.commit()
    cursor.execute("SELECT category_id FROM product_category")
    parent_ids = [row['category_id'] for row in cursor.fetchall()]

    cursor.execute("INSERT INTO product_category (name, parent_category_id, description) VALUES ('Subcategory 0', %s, %s), ('Subcategory 1', %s, %s), ('Subcategory 2', %s, %s), ('Subcategory 3', %s, %s), ('Subcategory 4', %s, %s)", 
                   (random.choice(parent_ids), fake.sentence(), random.choice(parent_ids), fake.sentence(), random.choice(parent_ids), fake.sentence(), random.choice(parent_ids), fake.sentence(), random.choice(parent_ids), fake.sentence()))

def create_product_dummy_data(cursor):
    cursor.execute("SELECT category_id FROM product_category")
    category_ids = [row['category_id'] for row in cursor.fetchall()]

    sku = f"SKU-{fake.unique.random_number(digits=8)}"
    name = fake.catch_phrase()
    brand = fake.company()
    description = fake.text(max_nb_chars=200)
    category_id = random.choice(category_ids) if category_ids else None
    unit_price = round(random.uniform(10.0, 1000.0), 2)
    unit_cost = round(unit_price * random.uniform(0.4, 0.7), 2)
    stock_quantity = random.randint(0, 500)
    reorder_level = random.randint(10, 50)
    is_active = True
    search_document = f"{name} {brand} {description}"

    sql = """
        INSERT INTO product (
            sku, name, brand, description, category_id, 
            unit_price, unit_cost, stock_quantity, reorder_level, 
            is_active, search_document
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    cursor.execute(sql, (
        sku, name, brand, description, category_id,
        unit_price, unit_cost, stock_quantity, reorder_level,
        is_active, search_document
    ))

def create_customer_address_dummy_data(cursor, cust_id):
    for kind in ['billing', 'shipping']:
        label = "Home" if kind == 'shipping' else "Office"
        sql = """
            INSERT INTO customer_address (
                customer_id, kind, label, line1, line2, 
                city, state_region, postal_code, country_code, is_default
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """
        cursor.execute(sql, (
            cust_id, kind, label, fake.street_address(), fake.secondary_address() if random.choice([True, False]) else None,
            fake.city(), fake.state_abbr(), fake.postcode(), fake.country_code(), True
        ))

def create_order_dummy_data(cursor):
    cursor.execute("SELECT customer_id FROM customer")
    customer_ids = [row['customer_id'] for row in cursor.fetchall()]
    cursor.execute("SELECT employee_id FROM employee")
    employee_ids = [row['employee_id'] for row in cursor.fetchall()]

    order_number = f"ORD-{fake.unique.random_number(digits=8)}"
    customer_id = random.choice(customer_ids)
    sales_rep_id = random.choice(employee_ids) if employee_ids else None
    status = random.choice(["pending", "paid", "shipped", "delivered", "cancelled"])
    method = random.choice(["credit_card", "paypal", "bank_transfer"])
    shipping_fee = round(random.uniform(0.0, 20.0), 2)
    tax_total = round(random.uniform(5.0, 50.0), 2)
    discount_total = round(random.uniform(0.0, 30.0), 2)
    currency = "USD"
    notes = fake.sentence() if random.choice([True, False]) else None

    sql = """
        INSERT INTO `order` (
            order_number, customer_id, sales_rep_id, status, 
            method, shipping_fee, tax_total, discount_total, 
            currency, notes
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    cursor.execute(sql, (
        order_number, customer_id, sales_rep_id, status,
        method, shipping_fee, tax_total, discount_total,
        currency, notes
    ))
    return cursor.lastrowid

def create_order_item_dummy_data(cursor):
    cursor.execute("SELECT order_id FROM `order` ORDER BY order_id DESC LIMIT 1")
    order_id = cursor.fetchone()['order_id']

    cursor.execute("SELECT product_id, unit_price, unit_cost FROM product")
    products = cursor.fetchall()

    num_items = random.randint(1, 3)
    selected_products = random.sample(products, min(num_items, len(products)))
    
    for prod in selected_products:
        quantity = random.randint(1, 5)
        unit_price = prod['unit_price']
        unit_cost = prod['unit_cost']
        discount = 0.00
        line_total = round(float(unit_price) * quantity - discount, 2)
        line_cost = round(float(unit_cost) * quantity, 2)

        sql = """
            INSERT INTO order_item (
                order_id, product_id, quantity, unit_price, 
                unit_cost, discount, line_total, line_cost
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """
        cursor.execute(sql, (
            order_id, prod['product_id'], quantity, unit_price,
            unit_cost, discount, line_total, line_cost
        ))

def create_order_status_history_dummy_data(cursor):
    cursor.execute("SELECT order_id FROM `order` ORDER BY order_id DESC LIMIT 1")
    order_id = cursor.fetchone()['order_id']

    new_status = random.choice(["pending", "paid", "shipped", "delivered"])
    source = "system"
    
    sql = """
        INSERT INTO order_status_history (
            order_id, old_status, new_status, source
        ) VALUES (%s, %s, %s, %s)
    """
    cursor.execute(sql, (order_id, None, new_status, source))

def main():
    connection = connect_db()
    num_records = 5
    try:
        with connection.cursor() as cursor:
            create_product_category_dummy_data(cursor)

            for _ in range(num_records):
                create_employee_dummy_data(cursor)
                # create_customer_dummy_data(cursor, num_records)
                
                # cursor.execute("SELECT LAST_INSERT_ID() AS id")
                # last_customer_id = cursor.fetchone()['id']
                # create_customer_address_dummy_data(cursor, last_customer_id)

                # create_product_dummy_data(cursor)

                # create_order_dummy_data(cursor)
                # create_order_item_dummy_data(cursor)
                # create_order_status_history_dummy_data(cursor)

            connection.commit()

    except Exception as e:
        print(f"An error occurred: {e}")
        connection.rollback()
    finally:
        connection.close()

if __name__ == "__main__":
    create_employee_table()
    main()