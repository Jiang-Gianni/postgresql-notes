package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strconv"
	"sync"
	"time"

	"github.com/Jiang-Gianni/postgresql-notes/db"
	"github.com/lib/pq"
)

func main() {
	var conninfo string = db.DATABASE_URL
	var err error

	done := make(chan struct{})
	closeOnce := sync.OnceFunc(func() { close(done) })
	reportProblem := func(ev pq.ListenerEventType, err error) {
		if err != nil {
			fmt.Println(err.Error())
		}
		if ev == pq.ListenerEventDisconnected {
			closeOnce()
		}
	}

	spawnListener := func(name string) {
		listener := pq.NewListener(conninfo, 10*time.Second, time.Minute, reportProblem)
		err = listener.Listen("events")
		if err != nil {
			panic(err)
		}

		fmt.Println("Start monitoring PostgreSQL...")
		for n := range listener.Notify {
			fmt.Println(name+" received data from channel [", n.Channel, "] :")
			// Prepare notification payload for pretty print
			var prettyJSON bytes.Buffer
			err := json.Indent(&prettyJSON, []byte(n.Extra), "", "\t")
			if err != nil {
				fmt.Println("Error processing JSON: ", err)
				return
			}
			fmt.Println(prettyJSON.String())
		}
	}

	for i := 0; i < 3; i++ {
		go spawnListener(strconv.Itoa(i))
	}

	<-done
}
