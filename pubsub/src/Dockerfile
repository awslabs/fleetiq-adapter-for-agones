FROM golang:1.13 as build-env

WORKDIR /go/src/pubsub
ADD . /go/src/pubsub

RUN go get -d -v ./...

RUN go build -o /go/bin/pubsub

FROM gcr.io/distroless/base
COPY --from=build-env /go/bin/pubsub /
CMD ["/pubsub"]