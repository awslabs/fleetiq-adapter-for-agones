package main

import (
	"encoding/json"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/gamelift"
	"github.com/go-redis/redis"
	"io/ioutil"
	"log"
	"os"
	"time"
)

const port = "6379"

type Groups struct {
	GameServerGroups []string
}

func main() {
	bs, err := ioutil.ReadFile("/etc/fleetiq/fleetiq.conf")
	if err != nil {
		log.Fatal(err)
	}
	var g Groups
	if err := json.Unmarshal(bs, &g); err != nil {
		log.Fatalf("JSON unmarshaling failed: %s", err)
	}
	publish(g)
}

func publish(g Groups) {
	rdb := redis.NewClient(&redis.Options{
		Addr:     os.Getenv("REDIS_URL") + ":" + port,
		//Password: "foobared",
	})
	sess := session.Must(session.NewSession(&aws.Config{Region: aws.String(os.Getenv("AWS_REGION"))}))
	svc := gamelift.New(sess)
	result, err := rdb.Ping().Result()
	if err != nil {
		log.Fatal("Could not establish a connection to Redis:", err)
	}
	log.Println("Established connection to Redis:", result)

	for {
		for _, gs := range g.GameServerGroups {
			params := &gamelift.DescribeGameServerInstancesInput{
				GameServerGroupName: &gs,
			}
			log.Println("Game server group", gs, "instance status")
			pageNum := 0
			err = svc.DescribeGameServerInstancesPages(params,
				func(page *gamelift.DescribeGameServerInstancesOutput, lastPage bool) bool {
					pageNum++
					for _, obj := range page.GameServerInstances {
						b, _ := json.Marshal(obj)
						log.Println(*obj.InstanceId, string(b))
						err := rdb.Publish(*obj.InstanceId, string(b)).Err()
						if err != nil {
							log.Println("An error occurred publishing data to Redis:", err)
						}
					}
					return pageNum <= len(page.GameServerInstances)
				},
			)
		}
		time.Sleep(time.Second * 60)
	}
}