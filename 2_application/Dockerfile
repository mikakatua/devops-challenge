# build stage
FROM golang:1.17-alpine AS builder
# Compile gcsfuse binary
ENV GOPATH /go
RUN apk add --no-cache git && \
    go get -u github.com/googlecloudplatform/gcsfuse
# Build the app
WORKDIR /go/src/app
COPY app .
RUN CGO_ENABLED=0 go test -v && go build -o /app

# final stage
FROM alpine:3.15
RUN apk add --no-cache fuse && \
    mkdir /static && \
    chown nobody /static
COPY --from=builder /go/bin/gcsfuse /usr/local/bin
COPY --from=builder /app /app
EXPOSE 8080
USER nobody
CMD ["/app"]
