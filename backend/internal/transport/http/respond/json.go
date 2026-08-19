// Created by Rodion Kholodov.

package respond

import (
	"encoding/json"
	"net/http"

	"github.com/londxz/HackatonYandex/backend/internal/transport/http/requestctx"
)

type ErrorEnvelope struct {
	Error ErrorPayload `json:"error"`
}

type ErrorPayload struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	RequestID string `json:"request_id"`
}

func JSON(w http.ResponseWriter, statusCode int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(statusCode)
	_ = json.NewEncoder(w).Encode(value)
}

func Error(w http.ResponseWriter, r *http.Request, statusCode int, code string, message string) {
	JSON(w, statusCode, ErrorEnvelope{
		Error: ErrorPayload{
			Code:      code,
			Message:   message,
			RequestID: requestctx.RequestID(r.Context()),
		},
	})
}
