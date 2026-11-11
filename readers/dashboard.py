"""Streamlit dashboard on gold, read through Horizon Catalog with PyIceberg (no Snowflake warehouse).

Run: scripts/dashboard.sh   (http://localhost:8501, refreshes every 30 s)
"""
import pandas as pd
import streamlit as st

import horizon

st.set_page_config(page_title="cdc-lab: today's sales", layout="wide")
st.title("Today's sales")  # "today" = latest change today (see horizon.summarize)
st.caption(f"{horizon.DATABASE}.{horizon.GOLD} through Horizon Catalog (Iceberg REST) with PyIceberg. Refreshes every 30 s.")


@st.cache_resource(ttl=3000)  # the catalog's token lasts 1 hour: build a new one before that
def gold_table():
    return horizon.catalog().load_table(horizon.GOLD)


def bar(counts: dict, label: str):
    st.bar_chart(pd.DataFrame({label: list(counts), "transactions": list(counts.values())}), x=label, y="transactions", horizontal=True)


@st.fragment(run_every="30s")
def body():
    table = gold_table()
    table.refresh()  # pick up the newest snapshot
    s = horizon.summarize(table.scan(selected_fields=horizon.COLUMNS).to_arrow())
    a, b, c = st.columns(3)
    a.metric("Transactions today", f"{s['transactions']:,}", help="Transactions whose latest change (insert or status update) was committed today; all statuses")
    b.metric("Total sales today (net)", f"{s['total_sales']:,.2f}")
    c.metric("Latest change in gold", s["latest_commit"][11:19] if s["latest_commit"] else "none", help=f"{s['day']}; gold lags the source by up to ~1 minute")
    left, right = st.columns(2)
    with left:
        st.subheader("By customer tier")
        bar(s["by_customer_tier"], "customer tier")
    with right:
        st.subheader("By product type")
        bar(s["by_product_type"], "product type")
    st.caption(f"{s['day']} · {s['rows_in_gold']:,} rows in gold (last 7 days)")


body()
