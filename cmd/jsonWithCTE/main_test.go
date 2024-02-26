package main

import (
	"net/http"
	"testing"
)

var s Server

func init() {
	go s.runServer()
}

func BenchmarkDatabase(b *testing.B) {
	for i := 0; i < b.N; i++ {
		if err := GetEndpoint(database); err != nil {
			b.Fail()
		}
	}
}

func BenchmarkApplication(b *testing.B) {
	for i := 0; i < b.N; i++ {
		if err := GetEndpoint(application); err != nil {
			b.Fail()
		}
	}
}

func GetEndpoint(endpoint string) error {
	resp, err := http.Get("http://localhost:3333" + endpoint)
	if err != nil {
		return err
	}
	return resp.Body.Close()
}
