"""Simulate OLTP traffic on public.transaction: 80% insert, 20% update, one action every N seconds."""
import os
import random
import time
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP

import psycopg
from dotenv import load_dotenv

load_dotenv()  # read .env in the current folder into os.environ

DSN = (
    f"host={os.getenv('PG_HOST', 'localhost')} port={os.getenv('PG_PORT', '5432')} "
    f"dbname={os.environ['PG_DB']} user={os.environ['PG_USER']} password={os.environ['PG_PASSWORD']}"
)
INTERVAL_SEC = float(os.getenv('GEN_INTERVAL_SEC', '10'))

# Weights roughly match the sample CSVs.
PAYMENT_METHODS = ['credit_card', 'debit_card', 'paypal', 'buy_now_pay_later', 'bank_transfer', 'gift_card']
PAYMENT_WEIGHTS = [44, 21, 16, 11, 5, 3]
CHANNELS = ['web', 'mobile_app', 'marketplace', 'in_store', 'phone']
CHANNEL_WEIGHTS = [46, 38, 11, 4, 1]

# Allowed status changes for an update. refunded / cancelled are final.
TRANSITIONS = {'pending': ['completed', 'cancelled'], 'completed': ['refunded']}


def money(x) -> Decimal:
    return Decimal(x).quantize(Decimal('0.01'), ROUND_HALF_UP)


def next_id(cur) -> str:
    """TXN + yyyymmdd + 6-digit sequence within the day, e.g. TXN20261104000001."""
    prefix = f"TXN{datetime.now():%Y%m%d}"
    cur.execute("SELECT max(transaction_id) FROM transaction WHERE transaction_id LIKE %s", (prefix + '%',))
    last = cur.fetchone()[0]
    return f"{prefix}{(int(last[-6:]) + 1 if last else 1):06d}"


def insert(conn) -> None:
    qty = random.choices([1, 2, 3, 4, 5, 6], weights=[50, 25, 12, 7, 4, 2])[0]
    unit_price = money(random.uniform(5, 490))
    unit_cost = money(unit_price * Decimal(str(random.uniform(0.4, 0.75))))
    discount = money(random.uniform(0, 0.29))
    gross = money(qty * unit_price)
    net = money(gross * (1 - discount))
    margin = money(net - qty * unit_cost)
    row = {
        'event_ts': datetime.now().replace(microsecond=0),
        'customer_id': random.randint(1001, 2203),
        'product_id': random.randint(1, 402),
        'campaign_id': random.randint(5001, 5018) if random.random() < 0.35 else None,
        'quantity': qty, 'unit_price': unit_price, 'unit_cost': unit_cost, 'discount_pct': discount,
        'gross_amount': gross, 'net_amount': net, 'margin_amount': margin,
        'currency': 'AUD',
        'payment_method': random.choices(PAYMENT_METHODS, PAYMENT_WEIGHTS)[0],
        'channel': random.choices(CHANNELS, CHANNEL_WEIGHTS)[0],
        'status': 'completed' if random.random() < 0.9 else 'pending',
    }
    with conn.transaction(), conn.cursor() as cur:
        row['transaction_id'] = next_id(cur)
        cols = ', '.join(row)
        vals = ', '.join(f"%({c})s" for c in row)
        cur.execute(f"INSERT INTO transaction ({cols}) VALUES ({vals})", row)
    print(f"{datetime.now():%H:%M:%S} INSERT {row['transaction_id']} {row['status']} net={net}")


def update(conn) -> None:
    with conn.transaction(), conn.cursor() as cur:
        cur.execute(
            "SELECT transaction_id, status FROM transaction "
            "WHERE status IN ('pending', 'completed') ORDER BY random() LIMIT 1"
        )
        found = cur.fetchone()
        if not found:
            print("UPDATE skipped: no updatable rows yet")
            return
        txn_id, old = found
        new = random.choice(TRANSITIONS[old])
        cur.execute("UPDATE transaction SET status = %s WHERE transaction_id = %s", (new, txn_id))
    print(f"{datetime.now():%H:%M:%S} UPDATE {txn_id} {old} -> {new}")


def main() -> None:
    print(f"Connecting to {os.getenv('PG_HOST', 'localhost')}:{os.getenv('PG_PORT', '5432')}, one action every {INTERVAL_SEC}s. Ctrl+C to stop.")
    with psycopg.connect(DSN) as conn:
        while True:
            insert(conn) if random.random() < 0.8 else update(conn)
            time.sleep(INTERVAL_SEC)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("stopped")
