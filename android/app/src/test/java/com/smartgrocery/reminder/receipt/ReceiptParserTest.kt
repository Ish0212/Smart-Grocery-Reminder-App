package com.smartgrocery.reminder.receipt

import org.junit.Assert.assertEquals
import org.junit.Test
import java.math.BigDecimal

class ReceiptParserTest {

    @Test
    fun itemLinesBecomeNamedPurchasesWithPrices() {
        val items = ReceiptParser.parse(listOf("MILK 2% GAL 3.49", "EGGS 3.99 F"))

        assertEquals(
            listOf(
                ReceiptItem("Milk 2% Gallon", BigDecimal("3.49"), 1),
                ReceiptItem("Eggs", BigDecimal("3.99"), 1),
            ),
            items,
        )
    }

    @Test
    fun aQuantityLineUnderANameTakesTheNameAndPrice() {
        val items = ReceiptParser.parse(listOf("BANANAS", "2 @ 1.99"))

        assertEquals(listOf(ReceiptItem("Bananas", BigDecimal("1.99"), 2)), items)
    }

    @Test
    fun totalsPaymentsAndDiscountsAreSkipped() {
        val items = ReceiptParser.parse(
            listOf(
                "BREAD 2.49",
                "COUPON -1.00",
                "SAVINGS 0.50",
                "SUBTOTAL 2.49",
                "TOTAL 2.49",
                "VISA **** 1234 2.49",
            ),
        )

        assertEquals(listOf(ReceiptItem("Bread", BigDecimal("2.49"), 1)), items)
    }

    @Test
    fun aProductWhoseMiddleWordIsASkipWordIsKept() {
        val items = ReceiptParser.parse(listOf("GREETING CARD 3.00"))

        assertEquals(listOf(ReceiptItem("Greeting Card", BigDecimal("3.00"), 1)), items)
    }

    @Test
    fun repeatedProductsMergeWithTheirQuantities() {
        val items = ReceiptParser.parse(listOf("APPLES 1.20", "APPLES 1.20"))

        assertEquals(listOf(ReceiptItem("Apples", BigDecimal("1.20"), 2)), items)
    }

    @Test
    fun skuNumbersAndSizeCodesAreDropped() {
        val cleaned = ReceiptParser.cleanName("1234567 CHKN BRST 16OZ")

        assertEquals("Chicken Breast", cleaned?.name)
    }
}
