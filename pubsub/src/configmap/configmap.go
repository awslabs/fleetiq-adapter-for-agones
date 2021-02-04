package configmap

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"log"
)

func CanRead() error {
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatal(err.Error())
	}
	// creates the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatal(err.Error())
	}
	_, err = clientset.CoreV1().ConfigMaps("default").Get("fleetiqconfig", metav1.GetOptions{})
	if err != nil {
		return err
	} else {
		return nil
	}
}
