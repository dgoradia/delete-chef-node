package main

import (
	"errors"
	"flag"
	"fmt"
	"io/ioutil"
	"os"
	"strings"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials/stscreds"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sns"
)

// Version : returns the version string
func Version() string {
	return "v0.2.0"
}

// PrintVersion : prints the version string
func PrintVersion() {
	fmt.Printf("Version %s\n", Version())
	os.Exit(0)
}

// Config : takes a file (ioutil)
type Config struct {
	file []byte
}

func (c *Config) mapFromConfig() map[string]string {
	m := make(map[string]string)
	for _, str := range strings.Split(string(c.file), "\n") {
		if str != "" {
			val := strings.Fields(str)
			m[val[0]] = strings.Replace(val[1], "'", "", 2)
		}
	}
	return m
}

func (c *Config) getNodeName() string {
	return c.mapFromConfig()["node_name"]
}

// func mapFromConfig(file []byte) map[string]string {
// 	m := make(map[string]string)
// 	for _, str := range strings.Split(string(file), "\n") {
// 		if str != "" {
// 			val := strings.Fields(str)
// 			m[val[0]] = strings.Replace(val[1], "'", "", 2)
// 		}
// 	}
// 	return m
// }

func checkError(e error) {
	if e != nil {
		fmt.Println(e)
		os.Exit(1)
	}
}

func findChefServerAPITopic(topics *[]*sns.Topic) (string, error) {
	for _, topic := range *topics {
		if strings.Contains(*topic.TopicArn, "chef_server_api") {
			return *topic.TopicArn, nil
		}
	}
	return "", errors.New("Could not find SNS topic: chef_server_api")
}

func buildSession(sess *session.Session, role string) (*session.Session, *aws.Config) {
	if role != "" {
		creds := stscreds.NewCredentials(sess, role)
		return sess, &aws.Config{Credentials: creds}
	}
	return sess, &aws.Config{}
}

func main() {
	var role string
	var topic string
	var node string
	var version *bool
	flag.StringVar(&role, "r", "", "Role to assume using STS Creds (Optional)")
	flag.StringVar(&topic, "t", "", "SNS Topic ARN (Optional)")
	flag.StringVar(&node, "n", "", "Node name (optional)")
	version = flag.Bool("v", false, "Print version")
	flag.Parse()

	if *version {
		PrintVersion()
	}

	// Create new AWS SDK session
	sess, err := session.NewSession(&aws.Config{Region: aws.String("us-west-2")})
	checkError(err)

	// Create new SNS client
	svc := sns.New(buildSession(sess, role))

	// Get list of topics
	topics, err := svc.ListTopics(&sns.ListTopicsInput{})
	checkError(err)
	// fmt.Println(topics)

	// Search for a chef_server_api topic, passing a pointer reference
	// instead of value.
	var topicArn string
	if topic != "" {
		topicArn = topic
	} else {
		topicArn, err = findChefServerAPITopic(&topics.Topics)
		checkError(err)
	}

	// Grab the value of node_name from the client.rb file read into memory
	// above, again, passing a pointer reference.
	var nodeName string
	if node != "" {
		nodeName = node
	} else {
		// We need to know the node name of the server that's registered on
		// the Chef Server. This is done upon instance creation via user-data
		// and appeneded to the client.rb file as node_name.
		// Read in the client.rb file into memory.
		file, err := ioutil.ReadFile("/etc/chef/client.rb")
		checkError(err)

		config := &Config{file}
		nodeName = config.getNodeName()
	}
	// nodeName := nodeName(&Config{file})

	// Like Python's try/catch
	defer func() {
		if err := recover(); err != nil {
			fmt.Fprintf(os.Stderr, "Exception: %v\n", err)
		}
	}()

	// Publish the message to SNS
	message, err := svc.Publish(&sns.PublishInput{
		Message:  &nodeName,
		TopicArn: &topicArn,
	})
	checkError(err)

	fmt.Println("Message Published Successfully, MessageId:", *message.MessageId)

}
