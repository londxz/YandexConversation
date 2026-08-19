// Created by Rodion Kholodov.

package requestctx

import "context"

type requestIDKey struct{}
type deviceIDKey struct{}

func WithRequestID(ctx context.Context, requestID string) context.Context {
	return context.WithValue(ctx, requestIDKey{}, requestID)
}

func RequestID(ctx context.Context) string {
	requestID, _ := ctx.Value(requestIDKey{}).(string)
	return requestID
}

func WithDeviceID(ctx context.Context, deviceID string) context.Context {
	return context.WithValue(ctx, deviceIDKey{}, deviceID)
}

func DeviceID(ctx context.Context) string {
	deviceID, _ := ctx.Value(deviceIDKey{}).(string)
	return deviceID
}
