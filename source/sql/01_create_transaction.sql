CREATE TABLE IF NOT EXISTS public.transaction (
  transaction_id  VARCHAR(20)    PRIMARY KEY,
  event_ts        TIMESTAMP      NOT NULL,
  customer_id     INTEGER        NOT NULL,
  product_id      INTEGER        NOT NULL,
  campaign_id     INTEGER,
  quantity        INTEGER        NOT NULL,
  unit_price      NUMERIC(10,2)  NOT NULL,
  unit_cost       NUMERIC(10,2)  NOT NULL,
  discount_pct    NUMERIC(4,2)   NOT NULL,
  gross_amount    NUMERIC(12,2)  NOT NULL,
  net_amount      NUMERIC(12,2)  NOT NULL,
  margin_amount   NUMERIC(12,2)  NOT NULL,
  currency        CHAR(3)        NOT NULL,
  payment_method  VARCHAR(30)    NOT NULL,
  channel         VARCHAR(30)    NOT NULL,
  status          VARCHAR(20)    NOT NULL
);
