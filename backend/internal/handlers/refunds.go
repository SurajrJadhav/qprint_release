package handlers

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"backend/internal/database"
	"backend/internal/notifications"
)

// refundContext describes why a refund is happening (for audit text).
type refundContext struct {
	UserID        int
	FileID        int
	PaymentOrderID int
	Reason        string // e.g. "Customer withdrawal before printing", "Customer account deleted", "Shopkeeper account deleted"
}

// refundForFile handles refund logic for a single file + payment order.
// It assumes the caller has already checked that the file is NOT downloaded.
// It verifies that the payment order and file belong to ctx.UserID before refunding (defense-in-depth).
func refundForFile(ctx refundContext) {
	// Ownership check: payment order must belong to user, and file must belong to that order and user.
	var ok int
	err := database.DB.QueryRow(context.Background(),
		`SELECT 1 FROM payment_orders po
		 INNER JOIN files f ON f.payment_order_id = po.id AND f.id = $1 AND f.user_id = po.user_id
		 WHERE po.id = $2 AND po.user_id = $3`,
		ctx.FileID, ctx.PaymentOrderID, ctx.UserID).Scan(&ok)
	if err != nil || ok != 1 {
		return
	}

	var paymentID *string
	var paymentStatus string
	var paymentAmount float64
	var paymentMethod string
	var walletAmount float64

	err = database.DB.QueryRow(context.Background(),
		`SELECT payment_id, status, amount, COALESCE(payment_method, 'razorpay'), COALESCE(wallet_amount, 0)
		 FROM payment_orders WHERE id = $1`,
		ctx.PaymentOrderID).Scan(&paymentID, &paymentStatus, &paymentAmount, &paymentMethod, &walletAmount)
	if err != nil {
		return
	}

	if paymentStatus != "paid" {
		return
	}

	description := ctx.Reason
	if description == "" {
		description = "Customer withdrawal before printing"
	}

	// Wallet-only payment
	if paymentMethod == "wallet" {
		tx, txErr := database.DB.Begin(context.Background())
		if txErr != nil {
			return
		}
		defer tx.Rollback(context.Background())

		var claimedID int
		txErr = tx.QueryRow(context.Background(),
			`UPDATE payment_orders SET status = 'refunded' WHERE id = $1 AND status = 'paid' RETURNING id`,
			ctx.PaymentOrderID).Scan(&claimedID)
		if errors.Is(txErr, sql.ErrNoRows) || txErr != nil {
			return
		}

		var balanceAfter float64
		txErr = tx.QueryRow(context.Background(),
			`UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + $1 WHERE id = $2 RETURNING wallet_balance`,
			paymentAmount, ctx.UserID).Scan(&balanceAfter)
		if txErr != nil {
			return
		}
		balanceBefore := balanceAfter - paymentAmount
		_, txErr = tx.Exec(context.Background(),
			`INSERT INTO wallet_transactions (user_id, transaction_type, amount, balance_before, balance_after, payment_order_id, status, description)
			 VALUES ($1, 'refund', $2, $3, $4, $5, 'completed', $6)`,
			ctx.UserID, paymentAmount, balanceBefore, balanceAfter, ctx.PaymentOrderID, description)
		if txErr != nil {
			return
		}

		// Mark all files in this order as refunded (single order = one refund)
		tx.Exec(context.Background(), `UPDATE files SET payment_status = 'refunded' WHERE payment_order_id = $1`, ctx.PaymentOrderID)
		tx.Exec(context.Background(),
			`UPDATE shopkeeper_payouts SET status = 'failed' WHERE payment_order_id = $1 AND status = 'pending'`,
			ctx.PaymentOrderID)
		tx.Commit(context.Background())
		notifications.SendToUser(ctx.UserID, "Refund processed", "Your refund of "+notifications.FormatAmount(paymentAmount)+" has been processed to your wallet.", map[string]string{"type": "refund"})
		return
	}

	// Hybrid: wallet + Razorpay
	if paymentMethod == "hybrid" && paymentID != nil && razorpayClient != nil {
		razorpayRefundAmount := paymentAmount - walletAmount
		if razorpayRefundAmount < 0.01 {
			razorpayRefundAmount = 0
		}

		tx, txErr := database.DB.Begin(context.Background())
		if txErr == nil {
			defer tx.Rollback(context.Background())
			var claimedID int
			txErr = tx.QueryRow(context.Background(),
				`UPDATE payment_orders SET status = 'refunded' WHERE id = $1 AND status = 'paid' RETURNING id`,
				ctx.PaymentOrderID).Scan(&claimedID)
			if !errors.Is(txErr, sql.ErrNoRows) && txErr == nil {
				if walletAmount > 0 {
					var balanceAfter float64
					txErr = tx.QueryRow(context.Background(),
						`UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + $1 WHERE id = $2 RETURNING wallet_balance`,
						walletAmount, ctx.UserID).Scan(&balanceAfter)
					if txErr == nil {
						balanceBefore := balanceAfter - walletAmount
						tx.Exec(context.Background(),
							`INSERT INTO wallet_transactions (user_id, transaction_type, amount, balance_before, balance_after, payment_order_id, status, description)
							 VALUES ($1, 'refund', $2, $3, $4, $5, 'completed', $6)`,
							ctx.UserID, walletAmount, balanceBefore, balanceAfter, ctx.PaymentOrderID, description)
					}
				}
				if txErr == nil {
					tx.Exec(context.Background(), `UPDATE files SET payment_status = 'refunded' WHERE payment_order_id = $1`, ctx.PaymentOrderID)
					tx.Exec(context.Background(),
						`UPDATE shopkeeper_payouts SET status = 'failed' WHERE payment_order_id = $1 AND status = 'pending'`,
						ctx.PaymentOrderID)
					tx.Commit(context.Background())
					notifications.SendToUser(ctx.UserID, "Refund processed", "Your refund of "+notifications.FormatAmount(paymentAmount)+" has been processed.", map[string]string{"type": "refund"})
				}
			}
		}

		if razorpayRefundAmount >= 0.01 {
			notes := map[string]string{"reason": description, "file_id": fmt.Sprintf("%d", ctx.FileID)}
			_, _ = razorpayClient.CreateRefund(*paymentID, &razorpayRefundAmount, notes)
		}
		return
	}

	// Pure Razorpay
	if paymentMethod == "razorpay" && paymentID != nil && razorpayClient != nil {
		var claimedID int
		errClaim := database.DB.QueryRow(context.Background(),
			`UPDATE payment_orders SET status = 'refunded' WHERE id = $1 AND status = 'paid' RETURNING id`,
			ctx.PaymentOrderID).Scan(&claimedID)
		if !errors.Is(errClaim, sql.ErrNoRows) && errClaim == nil {
			notes := map[string]string{"reason": description, "file_id": fmt.Sprintf("%d", ctx.FileID)}
			refundResp, refundErr := razorpayClient.CreateRefund(*paymentID, &paymentAmount, notes)
			if refundErr == nil && refundResp != nil {
				database.DB.Exec(context.Background(), `UPDATE files SET payment_status = 'refunded' WHERE payment_order_id = $1`, ctx.PaymentOrderID)
				database.DB.Exec(context.Background(),
					`UPDATE shopkeeper_payouts SET status = 'failed' WHERE payment_order_id = $1 AND status = 'pending'`,
					ctx.PaymentOrderID)
				notifications.SendToUser(ctx.UserID, "Refund processed", "Your refund of "+notifications.FormatAmount(paymentAmount)+" has been processed.", map[string]string{"type": "refund"})
			} else {
				// optional: revert payment_orders.status to 'paid' on failure
			}
		}
	}
}

