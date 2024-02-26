package main

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"

	"github.com/Jiang-Gianni/postgresql-notes/db"
	"github.com/Jiang-Gianni/postgresql-notes/sqlc"
)

type Server struct {
	q *sqlc.Queries
}

const database = "/database"
const application = "/application"

func (s *Server) runServer() error {
	sqlDB, err := sql.Open("postgres", db.DATABASE_URL)
	if err != nil {
		return err
	}
	defer sqlDB.Close()
	s.q = sqlc.New(sqlDB)
	http.HandleFunc(database, s.databaseHandler())
	http.HandleFunc(application, s.applicationHandler())
	return http.ListenAndServe(":3333", nil)
}

func (s *Server) databaseHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		payload, err := s.q.DndRecursiveJSON(r.Context())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Header().Add("Content-Type", "application/json")
		w.Write(payload)
	}
}

func (s *Server) applicationHandler() http.HandlerFunc {
	type ResponseStruct struct {
		Name       string            `json:"Name"`
		SubClasses []*ResponseStruct `json:"Sub Classes,omitempty"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		dndList, err := s.q.DndGetClasses(r.Context())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		rootMap := map[int32]*ResponseStruct{}
		childrenMap := map[int32]*ResponseStruct{}

		for _, dndClass := range dndList {
			resp := &ResponseStruct{
				Name:       dndClass.Name.String,
				SubClasses: []*ResponseStruct{},
			}
			if !dndClass.ParentID.Valid {
				// Root element
				rootMap[dndClass.ID] = resp
			}

			childrenMap[dndClass.ID] = resp
		}

		for _, dndClass := range dndList {
			if !dndClass.ParentID.Valid {
				// Root element
				continue
			}
			childrenMap[dndClass.ParentID.Int32].SubClasses = append(
				childrenMap[dndClass.ParentID.Int32].SubClasses,
				childrenMap[dndClass.ID],
			)
		}

		payload := []ResponseStruct{}
		for _, root := range rootMap {
			payload = append(payload, *root)
		}
		if err := json.NewEncoder(w).Encode(payload); err != nil {
			log.Fatal(err)
		}

	}
}
