
create or replace PACKAGE BODY SS_PKG_POSTING_ENGINE_C AS


/* =========================================
   GET GLOBAL AVG COST
========================================= */
FUNCTION GET_ITEM_AVG_COST (
    P_ITEM_ID NUMBER
) RETURN NUMBER
IS
    V_COST NUMBER := 0;
BEGIN

    SELECT AVG_COST
    INTO V_COST
    FROM SS_ITEM_COST
    WHERE ITEM_ID = P_ITEM_ID;

    RETURN V_COST;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0;

END;



/* =========================================
   UPDATE GLOBAL ITEM COST
========================================= */
PROCEDURE UPDATE_GLOBAL_ITEM_COST(
    P_ITEM_ID NUMBER,
    P_QTY_IN NUMBER,
    P_UNIT_COST NUMBER
)
IS

    V_OLD_QTY NUMBER := 0;
    V_OLD_VAL NUMBER := 0;

    V_NEW_QTY NUMBER;
    V_NEW_VAL NUMBER;
    V_NEW_AVG NUMBER;

BEGIN

    BEGIN

        SELECT TOTAL_QTY, TOTAL_VALUE
        INTO V_OLD_QTY, V_OLD_VAL
        FROM SS_ITEM_COST
        WHERE ITEM_ID = P_ITEM_ID
        FOR UPDATE;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN

            INSERT INTO SS_ITEM_COST
            VALUES (P_ITEM_ID,0,0,0);

            V_OLD_QTY := 0;
            V_OLD_VAL := 0;

    END;

    V_NEW_QTY := V_OLD_QTY + P_QTY_IN;

    V_NEW_VAL := V_OLD_VAL + (P_QTY_IN * P_UNIT_COST);

    IF V_NEW_QTY = 0 THEN
        V_NEW_AVG := 0;
    ELSE
        V_NEW_AVG := V_NEW_VAL / V_NEW_QTY;
    END IF;

    UPDATE SS_ITEM_COST
    SET TOTAL_QTY   = V_NEW_QTY,
        TOTAL_VALUE = V_NEW_VAL,
        AVG_COST    = V_NEW_AVG
    WHERE ITEM_ID = P_ITEM_ID;

END;



/* =========================================
   INCREASE STORE QUANTITY
========================================= */
PROCEDURE UPDATE_ITEM_BALANCE (
    P_ITEM_ID NUMBER,
    P_STORE_ID NUMBER,
    P_QTY_IN NUMBER
)
IS

    V_QTY NUMBER := 0;

BEGIN

    BEGIN

        SELECT QTY
        INTO V_QTY
        FROM SS_ITEM_STORE_BAL
        WHERE ITEM_ID = P_ITEM_ID
        AND STORE_ID = P_STORE_ID
        FOR UPDATE;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN

            INSERT INTO SS_ITEM_STORE_BAL
            (SS_BAL_ID, ITEM_ID, STORE_ID, QTY)
            VALUES
            (SS_SEQ_ITEM_STORE_BAL.NEXTVAL,
             P_ITEM_ID,
             P_STORE_ID,
             0);

            V_QTY := 0;

    END;

    UPDATE SS_ITEM_STORE_BAL
    SET QTY = V_QTY + P_QTY_IN
    WHERE ITEM_ID = P_ITEM_ID
    AND STORE_ID = P_STORE_ID;

END;



/* =========================================
   REDUCE STORE STOCK
========================================= */
PROCEDURE REDUCE_STOCK (
    P_ITEM_ID NUMBER,
    P_STORE_ID NUMBER,
    P_QTY_OUT NUMBER
)
IS

    V_QTY NUMBER;

BEGIN

    SELECT QTY
    INTO V_QTY
    FROM SS_ITEM_STORE_BAL
    WHERE ITEM_ID = P_ITEM_ID
    AND STORE_ID = P_STORE_ID
    FOR UPDATE;

    IF V_QTY < P_QTY_OUT THEN
        RAISE_APPLICATION_ERROR(-20002,'Negative stock not allowed');
    END IF;

    UPDATE SS_ITEM_STORE_BAL
    SET QTY = V_QTY - P_QTY_OUT
    WHERE ITEM_ID = P_ITEM_ID
    AND STORE_ID = P_STORE_ID;

END;

/* ===========================================================
   PRIVATE: GET ACCOUNT ID FROM CONFIG
   =========================================================== */
FUNCTION GET_ACCOUNT_ID (
    P_TRX_TYPE    VARCHAR2,
    P_ROLE        VARCHAR2
) RETURN NUMBER IS

    V_ACCOUNT_ID NUMBER;

BEGIN
    SELECT ACCOUNT_ID
    INTO   V_ACCOUNT_ID
    FROM   SS_ACCOUNT_CONFIG
    WHERE  TRX_TYPE = P_TRX_TYPE
    AND    ACCOUNT_ROLE = P_ROLE;

    RETURN V_ACCOUNT_ID;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20050,
        'Account not configured for ' || P_TRX_TYPE || ' - ' || P_ROLE);
END;

/* ===========================================================
   PRIVATE: INSERT_STOCK_MOVEMENT
   =========================================================== */
PROCEDURE INSERT_STOCK_MOVEMENT
(
    P_TRX_TYPE   VARCHAR2,
    P_TRX_ID     NUMBER,
    P_ITEM_ID    NUMBER,
    P_STORE_ID   NUMBER,
    P_QTY_IN     NUMBER,
    P_QTY_OUT    NUMBER,
    P_UNIT_COST  NUMBER
)
IS
BEGIN

INSERT INTO SS_STOCK_MOVEMENTS
(
  
    TRX_TYPE,
    TRX_ID,
    ITEM_ID,
    STORE_ID,
    QTY_IN,
    QTY_OUT,
    UNIT_COST,
    TOTAL_COST,
    TRX_DATE
)
VALUES
(
 
    P_TRX_TYPE,
    P_TRX_ID,
    P_ITEM_ID,
    P_STORE_ID,
    P_QTY_IN,
    P_QTY_OUT,
    P_UNIT_COST,
    (P_QTY_IN - P_QTY_OUT) * P_UNIT_COST,
    SYSDATE
);

END;


/* =========================================
   PRIVATE: REVERSE_JOURNAL
========================================= */
PROCEDURE REVERSE_JOURNAL (
    P_TRX_TYPE VARCHAR2,
    P_TRX_ID   NUMBER,
    P_NEW_TYPE VARCHAR2)
IS

    V_OLD_JID NUMBER;
    V_NEW_JID NUMBER;

BEGIN

    SELECT SS_JOURNAL_ID
    INTO V_OLD_JID
    FROM SS_JOURNAL_HDR
    WHERE TRX_TYPE = P_TRX_TYPE
    AND TRX_ID = P_TRX_ID;

    V_NEW_JID := SS_SEQ_JOURNAL_HDR.NEXTVAL;

    INSERT INTO SS_JOURNAL_HDR
    (
    SS_JOURNAL_ID,
    TRX_TYPE,
    TRX_ID,
    TRX_DATE,
    DESCRIPTION
    )
    VALUES
    (
    V_NEW_JID,
    P_NEW_TYPE,
    P_TRX_ID,
    SYSDATE,
    'Reversal of '||P_TRX_TYPE
    );

    FOR R IN (
        SELECT ACCOUNT_ID,
           DEBIT,
           CREDIT
        FROM SS_JOURNAL_LINES
        WHERE JOURNAL_ID = V_OLD_JID )
    LOOP

    INSERT INTO SS_JOURNAL_LINES
    (
    SS_LINE_ID,
    JOURNAL_ID,
    ACCOUNT_ID,
    DEBIT,
    CREDIT
    )
    VALUES
    (
    SS_SEQ_JOURNAL_LINES.NEXTVAL,
    V_NEW_JID,
    R.ACCOUNT_ID,
    R.CREDIT,
    R.DEBIT
    );

    END LOOP;

END;


/* =========================================
   POST PURCHASE
========================================= */
PROCEDURE POST_PURCHASE (P_PURCHASE_ID NUMBER) IS

    CURSOR C_LINES IS
        SELECT *
        FROM SS_PURCHASE_LINES1
        WHERE PURCHASE_ID = P_PURCHASE_ID;

    V_STORE_ID NUMBER;
    V_STATUS VARCHAR2(20);
    V_JOURNAL_ID   NUMBER;
    V_SUBTOTAL     NUMBER := 0;
    V_TOTAL        NUMBER := 0;

BEGIN

    SELECT STORE_ID, STATUS
    INTO V_STORE_ID, V_STATUS
    FROM SS_PURCHASE_HDR
    WHERE SS_PURCHASE_ID = P_PURCHASE_ID
    FOR UPDATE;

    IF V_STATUS <> 'DRAFT' THEN
        RAISE_APPLICATION_ERROR(-20001,
        'Only DRAFT purchase can be posted');
    END IF;

    FOR R IN C_LINES LOOP

        /* update global item cost */
        UPDATE_GLOBAL_ITEM_COST(
            R.ITEM_ID,
            R.QTY,
            R.UNIT_PRICE_LC
        );

        /* update store quantity */
        UPDATE_ITEM_BALANCE(
            R.ITEM_ID,
            V_STORE_ID,
            R.QTY
        );

        V_SUBTOTAL := V_SUBTOTAL + (R.QTY * R.UNIT_PRICE_LC);
        V_TOTAL := V_TOTAL + (R.QTY * R.UNIT_PRICE_LC);

        /* insert stock movment */
        INSERT_STOCK_MOVEMENT(
            'PURCHASE',
            P_PURCHASE_ID,
            R.ITEM_ID,
            V_STORE_ID,
            R.QTY,
            0,
            R.UNIT_PRICE_LC
        );

    END LOOP;
    -- Journal
    V_JOURNAL_ID := SS_SEQ_JOURNAL_HDR.NEXTVAL;

    INSERT INTO SS_JOURNAL_HDR

    VALUES (V_JOURNAL_ID, P_PURCHASE_ID, SYSDATE, 'Purchase Posting',1,'PURCHASE');

    DECLARE
        V_INV_ACC NUMBER;
        V_AP_ACC  NUMBER;
    BEGIN

        V_INV_ACC := GET_ACCOUNT_ID('PURCHASE','INVENTORY');
        V_AP_ACC  := GET_ACCOUNT_ID('PURCHASE','AP');

        INSERT INTO SS_JOURNAL_LINES
        VALUES (SS_SEQ_JOURNAL_LINES.NEXTVAL,
                V_JOURNAL_ID,
                V_INV_ACC,
                V_SUBTOTAL,
                0);

        INSERT INTO SS_JOURNAL_LINES
        VALUES (SS_SEQ_JOURNAL_LINES.NEXTVAL,
                V_JOURNAL_ID,
                V_AP_ACC,
             0,
                V_TOTAL);

    END;

    UPDATE SS_PURCHASE_HDR
    SET STATUS = 'POSTED'
    WHERE SS_PURCHASE_ID = P_PURCHASE_ID;

END;



/* =========================================
   POST TRANSFER
========================================= */
PROCEDURE POST_TRANSFER (P_TRANSFER_ID NUMBER) IS

    CURSOR C_LINES IS
        SELECT *
        FROM SS_TRANSFER_LINES1
        WHERE TRANSFER_ID = P_TRANSFER_ID;

    V_FROM_STORE NUMBER;
    V_TO_STORE NUMBER;
    V_STATUS VARCHAR2(20);

BEGIN

    SELECT FROM_STORE_ID, TO_STORE_ID, STATUS
    INTO V_FROM_STORE, V_TO_STORE, V_STATUS
    FROM SS_TRANSFER_HDR
    WHERE SS_TRANSFER_ID = P_TRANSFER_ID
    FOR UPDATE;

    IF V_STATUS <> 'DRAFT' THEN
        RAISE_APPLICATION_ERROR(-20010,
        'Only DRAFT transfers can be posted');
    END IF;

    FOR R IN C_LINES LOOP
        /* reduce stock */
        REDUCE_STOCK(
            R.ITEM_ID,
            V_FROM_STORE,
            R.QTY
        );

        UPDATE_ITEM_BALANCE(
            R.ITEM_ID,
            V_TO_STORE,
            R.QTY
        );

        /* out movement */
        INSERT_STOCK_MOVEMENT(
            'TRANSFER_OUT',
            P_TRANSFER_ID,
            R.ITEM_ID,
            V_FROM_STORE,
            0,
            R.QTY,
            GET_ITEM_AVG_COST(R.ITEM_ID)
        );

        /* In movement */
        INSERT_STOCK_MOVEMENT(
            'TRANSFER_IN',
            P_TRANSFER_ID,
            R.ITEM_ID,
            V_TO_STORE,
            R.QTY,
            0,
            GET_ITEM_AVG_COST(R.ITEM_ID)
        );

    END LOOP;

    UPDATE SS_TRANSFER_HDR
    SET STATUS = 'POSTED'
    WHERE SS_TRANSFER_ID = P_TRANSFER_ID;

END;



/* =========================================
   POST SALE
========================================= */
PROCEDURE POST_SALE (P_SALES_ID NUMBER) IS

    CURSOR C_LINES IS
        SELECT *
        FROM SS_SALES_LINES1
        WHERE SALES_ID = P_SALES_ID;

    V_STORE_ID NUMBER;
    V_STATUS VARCHAR2(20);

    V_COST NUMBER;

    V_JOURNAL_ID    NUMBER;

    V_TOTAL_REV     NUMBER := 0;
    V_TOTAL_COGS    NUMBER := 0;
    V_TOTAL_VAT     NUMBER := 0;

    V_UNIT_COST     NUMBER;

BEGIN

    SELECT STORE_ID, STATUS
    INTO V_STORE_ID, V_STATUS
    FROM SS_SALES_HDR
    WHERE SS_SALES_ID = P_SALES_ID
    FOR UPDATE;

    IF V_STATUS <> 'DRAFT' THEN
        RAISE_APPLICATION_ERROR(-20003,
        'Only DRAFT sales can be posted');
    END IF;

    FOR R IN C_LINES LOOP

        REDUCE_STOCK(
            R.ITEM_ID,
            V_STORE_ID,
            R.QTY
        );

        /* get global cost for COGS */
        V_COST := GET_ITEM_AVG_COST(R.ITEM_ID);

        /* stock movement */
        INSERT_STOCK_MOVEMENT(
            'SALE',
            P_SALES_ID,
            R.ITEM_ID,
            V_STORE_ID,
            0,
            R.QTY,
            V_COST
        );

        UPDATE SS_SALES_LINES1
        SET COST_AMOUNT = R.QTY * V_COST,
            PROFIT_AMOUNT = (R.QTY * R.UNIT_PRICE_LC) - (R.QTY * V_COST)
        WHERE SS_SALES_LINE_ID = R.SS_SALES_LINE_ID;

        V_TOTAL_REV := V_TOTAL_REV + (R.QTY * R.UNIT_PRICE_LC);
        V_TOTAL_COGS := V_TOTAL_COGS + (R.QTY * V_COST);

    END LOOP;

    
    -- Journal
    V_JOURNAL_ID := SS_SEQ_JOURNAL_HDR.NEXTVAL;

    INSERT INTO SS_JOURNAL_HDR
    (
        SS_JOURNAL_ID,
        TRX_TYPE,
        TRX_ID,
        TRX_DATE,
        DESCRIPTION
    )
    VALUES
    (
        V_JOURNAL_ID,
        'SALE',
        P_SALES_ID,
        SYSDATE,
        'Sales Posting'
    );

    DECLARE
        V_AR_ACC     NUMBER;
        V_REV_ACC    NUMBER;
        V_VAT_ACC    NUMBER;
        V_COGS_ACC   NUMBER;
        V_INV_ACC    NUMBER;
    BEGIN

        V_AR_ACC   := GET_ACCOUNT_ID('SALE','AR');
        V_REV_ACC  := GET_ACCOUNT_ID('SALE','REVENUE');
        V_VAT_ACC  := GET_ACCOUNT_ID('SALE','VAT');
        V_COGS_ACC := GET_ACCOUNT_ID('SALE','COGS');
        V_INV_ACC  := GET_ACCOUNT_ID('SALE','INVENTORY');

        -- AR
        INSERT INTO SS_JOURNAL_LINES
        VALUES (SS_SEQ_JOURNAL_LINES.NEXTVAL,
                V_JOURNAL_ID,
                V_AR_ACC,
                V_TOTAL_REV + V_TOTAL_VAT,
                0);

        -- Revenue
        INSERT INTO SS_JOURNAL_LINES
        VALUES (SS_SEQ_JOURNAL_LINES.NEXTVAL,
                V_JOURNAL_ID,
                V_REV_ACC,
                0,
                V_TOTAL_REV);

        -- VAT
        IF V_TOTAL_VAT > 0 THEN
            INSERT INTO SS_JOURNAL_LINES
            VALUES (SS_SEQ_JOURNAL_LINES.NEXTVAL,
                    V_JOURNAL_ID,
                    V_VAT_ACC,
                    0,
                    V_TOTAL_VAT);
        END IF;

        -- COGS
        INSERT INTO SS_JOURNAL_LINES
        VALUES (SS_SEQ_JOURNAL_LINES.NEXTVAL,
                V_JOURNAL_ID,
                V_COGS_ACC,
                V_TOTAL_COGS,
                0);

        -- Inventory
        INSERT INTO SS_JOURNAL_LINES
        VALUES (SS_SEQ_JOURNAL_LINES.NEXTVAL,
                V_JOURNAL_ID,
                V_INV_ACC,
                0,
             V_TOTAL_COGS);

    END;

    UPDATE SS_SALES_HDR
    SET STATUS = 'POSTED'
    WHERE SS_SALES_ID = P_SALES_ID;

END;


/* ===========================================================
   PUBLIC: POST CUSTOMER RECEIPT
   =========================================================== */
PROCEDURE POST_RECEIPT (P_RECEIPT_ID NUMBER) IS

    V_STATUS        VARCHAR2(20);
    V_JOURNAL_ID    NUMBER;

    V_CUST_ID       NUMBER;
    V_AMOUNT        NUMBER;

    V_CASH_ACC      NUMBER;
    V_AR_ACC        NUMBER;

BEGIN

    -- Lock receipt
    SELECT STATUS, CUSTOMER_ID, AMOUNT_LC
    INTO   V_STATUS, V_CUST_ID, V_AMOUNT
    FROM   SS_RECEIPTS
    WHERE  SS_RECEIPT_ID = P_RECEIPT_ID
    FOR UPDATE;

    IF V_STATUS <> 'DRAFT' THEN
        RAISE_APPLICATION_ERROR(-20040,
        'Only DRAFT receipts can be posted');
    END IF;

    -- Get accounts
    V_CASH_ACC := GET_ACCOUNT_ID('RECEIPT','CASH');
    V_AR_ACC   := GET_ACCOUNT_ID('RECEIPT','AR');

    -- Journal Header
    V_JOURNAL_ID := SS_SEQ_JOURNAL_HDR.NEXTVAL;

    INSERT INTO SS_JOURNAL_HDR
    VALUES (V_JOURNAL_ID,
            P_RECEIPT_ID,
            SYSDATE,
            'Customer Receipt Posting',
            4,
            'RECEIPT');

    -- Debit Cash
    INSERT INTO SS_JOURNAL_LINES
    VALUES (SS_SEQ_JOURNAL_LINES.NEXTVAL,
            V_JOURNAL_ID,
            V_CASH_ACC,
            V_AMOUNT,
            0);

    -- Credit AR
    INSERT INTO SS_JOURNAL_LINES
    VALUES (SS_SEQ_JOURNAL_LINES.NEXTVAL,
            V_JOURNAL_ID,
            V_AR_ACC,
            0,
            V_AMOUNT);

    -- Update status
    UPDATE SS_RECEIPTS
    SET STATUS = 'POSTED'
    WHERE SS_RECEIPT_ID = P_RECEIPT_ID;

END POST_RECEIPT;


/* ===========================================================
   PUBLIC: POST SUPPLIER PAYMENT
   =========================================================== */
PROCEDURE POST_SUPPLIER_PAYMENT (P_PAYMENT_ID NUMBER) IS

    V_STATUS        VARCHAR2(20);
    V_JOURNAL_ID    NUMBER;

    V_SUPP_ID       NUMBER;
    V_AMOUNT        NUMBER;

    V_CASH_ACC      NUMBER;
    V_AP_ACC        NUMBER;

BEGIN

    SELECT STATUS, SUPPLIER_ID, AMOUNT_LC
    INTO   V_STATUS, V_SUPP_ID, V_AMOUNT
    FROM   SS_SUPPLIER_PAYMENTS
    WHERE  SS_PAYMENT_ID = P_PAYMENT_ID
    FOR UPDATE;

    IF V_STATUS <> 'DRAFT' THEN
        RAISE_APPLICATION_ERROR(-20041,
        'Only DRAFT supplier payments can be posted');
    END IF;

    V_CASH_ACC := GET_ACCOUNT_ID('SUPPLIER_PAYMENT','CASH');
    V_AP_ACC   := GET_ACCOUNT_ID('SUPPLIER_PAYMENT','AP');

    V_JOURNAL_ID := SS_SEQ_JOURNAL_HDR.NEXTVAL;

    INSERT INTO SS_JOURNAL_HDR
    VALUES (V_JOURNAL_ID,
            P_PAYMENT_ID,
            SYSDATE,
            'Supplier Payment Posting',
            5,
            'SUPPLIER_PAYMENT');

    -- Debit AP
    INSERT INTO SS_JOURNAL_LINES
    VALUES (SS_SEQ_JOURNAL_LINES.NEXTVAL,
            V_JOURNAL_ID,
            V_AP_ACC,
            V_AMOUNT,
            0);

    -- Credit Cash
    INSERT INTO SS_JOURNAL_LINES
    VALUES (SS_SEQ_JOURNAL_LINES.NEXTVAL,
            V_JOURNAL_ID,
            V_CASH_ACC,
            0,
            V_AMOUNT);

    UPDATE SS_SUPPLIER_PAYMENTS
    SET STATUS = 'POSTED'
    WHERE SS_PAYMENT_ID = P_PAYMENT_ID;


END POST_SUPPLIER_PAYMENT;

/* ===========================================================
   PUBLIC: Cancel Purchase Procedure
   =========================================================== */
PROCEDURE CANCEL_PURCHASE (P_PURCHASE_ID NUMBER) IS

    CURSOR C_LINES IS
    SELECT *
    FROM SS_PURCHASE_LINES1
    WHERE PURCHASE_ID = P_PURCHASE_ID;

    V_STORE_ID NUMBER;
    V_STATUS   VARCHAR2(20);
    V_COST     NUMBER;

BEGIN

    SELECT STORE_ID, STATUS
    INTO V_STORE_ID, V_STATUS
    FROM SS_PURCHASE_HDR
    WHERE SS_PURCHASE_ID = P_PURCHASE_ID
    FOR UPDATE;

    IF V_STATUS <> 'POSTED' THEN
        RAISE_APPLICATION_ERROR(-20020,'Only POSTED purchase can be cancelled');
    END IF;

    FOR R IN C_LINES LOOP

        V_COST := GET_ITEM_AVG_COST(R.ITEM_ID);

        REDUCE_STOCK(
            R.ITEM_ID,
            V_STORE_ID,
            R.QTY
        );

        INSERT_STOCK_MOVEMENT(
            'PURCHASE_CANCEL',
            P_PURCHASE_ID,
            R.ITEM_ID,
            V_STORE_ID,
            0,
            R.QTY,
            V_COST
        );

    END LOOP;

    /* reverse accounting */
    REVERSE_JOURNAL('PURCHASE',P_PURCHASE_ID,'PURCHASE_CANCEL');

    UPDATE SS_PURCHASE_HDR
    SET STATUS='CANCELLED'
    WHERE SS_PURCHASE_ID=P_PURCHASE_ID;

END;


/* ===========================================================
   PUBLIC: Cancel Sale
   =========================================================== */
PROCEDURE CANCEL_SALE (P_SALES_ID NUMBER) IS

    CURSOR C_LINES IS
    SELECT *
    FROM SS_SALES_LINES1
    WHERE SALES_ID = P_SALES_ID;

    V_STORE_ID NUMBER;
    V_STATUS   VARCHAR2(20);
    V_COST     NUMBER;

BEGIN

    SELECT STORE_ID, STATUS
    INTO V_STORE_ID, V_STATUS
    FROM SS_SALES_HDR
    WHERE SS_SALES_ID = P_SALES_ID
    FOR UPDATE;

    IF V_STATUS <> 'POSTED' THEN
        RAISE_APPLICATION_ERROR(-20021,'Only POSTED sale can be cancelled');
    END IF;

    FOR R IN C_LINES LOOP

        V_COST := GET_ITEM_AVG_COST(R.ITEM_ID);

        UPDATE_ITEM_BALANCE(
            R.ITEM_ID,
            V_STORE_ID,
            R.QTY
        );

        INSERT_STOCK_MOVEMENT(
            'SALE_CANCEL',
            P_SALES_ID,
            R.ITEM_ID,
            V_STORE_ID,
            R.QTY,
            0,
            V_COST
        );

    END LOOP;

    /* reverse accounting */
    REVERSE_JOURNAL('SALE',P_SALES_ID,'SALE_CANCEL');

    UPDATE SS_SALES_HDR
    SET STATUS='CANCELLED'
    WHERE SS_SALES_ID=P_SALES_ID;

END; 

/* ===========================================================
   PUBLIC: Cancel Transfer
   =========================================================== */
PROCEDURE CANCEL_TRANSFER (P_TRANSFER_ID NUMBER) IS

    CURSOR C_LINES IS
    SELECT *
    FROM SS_TRANSFER_LINES1
    WHERE TRANSFER_ID = P_TRANSFER_ID;

    V_FROM_STORE NUMBER;
    V_TO_STORE NUMBER;
    V_STATUS VARCHAR2(20);
    V_COST NUMBER;

BEGIN

    SELECT FROM_STORE_ID, TO_STORE_ID, STATUS
    INTO V_FROM_STORE, V_TO_STORE, V_STATUS
    FROM SS_TRANSFER_HDR
    WHERE SS_TRANSFER_ID = P_TRANSFER_ID
    FOR UPDATE;

    IF V_STATUS <> 'POSTED' THEN
        RAISE_APPLICATION_ERROR(-20022,'Only POSTED transfer can be cancelled');
    END IF;

    FOR R IN C_LINES LOOP

        V_COST := GET_ITEM_AVG_COST(R.ITEM_ID);

        /* return stock to source */
        UPDATE_ITEM_BALANCE(
            R.ITEM_ID,
            V_FROM_STORE,
            R.QTY
        );

        /* remove stock from destination */
        REDUCE_STOCK(
            R.ITEM_ID,
            V_TO_STORE,
            R.QTY
        );

        INSERT_STOCK_MOVEMENT(
            'TRANSFER_CANCEL_OUT',
            P_TRANSFER_ID,
            R.ITEM_ID,
            V_TO_STORE,
            0,
            R.QTY,
            V_COST
        );

        INSERT_STOCK_MOVEMENT(
            'TRANSFER_CANCEL_IN',
            P_TRANSFER_ID,
            R.ITEM_ID,
            V_FROM_STORE,
            R.QTY,
            0,
            V_COST
        );

    END LOOP;

    UPDATE SS_TRANSFER_HDR
        SET STATUS = 'CANCELLED'
        WHERE SS_TRANSFER_ID = P_TRANSFER_ID;

END;   

END SS_PKG_POSTING_ENGINE_C;
