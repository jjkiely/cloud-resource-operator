package e2e

import (
	"testing"
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	"sigs.k8s.io/controller-runtime/pkg/envtest"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	crov1alpha1 "github.com/integr8ly/cloud-resource-operator/apis/integreatly/v1alpha1"
)


// These tests use Ginkgo (BDD-style Go testing framework). Refer to
// http://onsi.github.io/ginkgo/ to learn more about Ginkgo.

var cfg *rest.Config
var testEnv *envtest.Environment
var err error

func TestAPIs(t *testing.T) {
	RegisterFailHandler(Fail)

	// start test env
	By("bootstrapping test environment")

	useCluster := true
	testEnv = &envtest.Environment{
		UseExistingCluster:       &useCluster,
		AttachControlPlaneOutput: true,
	}
	cfg, err = testEnv.Start()
	if err != nil {
		t.Fatalf("could not get start test environment %s", err)
	}
	cfg.Impersonate = rest.ImpersonationConfig{
		UserName: "system:admin",
		Groups:   []string{"system:authenticated"},
	}
}

var _ = BeforeSuite(func(done Done) {
	logf.SetLogger(zap.LoggerTo(GinkgoWriter, true))

	err = crov1alpha1.AddToScheme(scheme.Scheme)
	Expect(err).NotTo(HaveOccurred())

	// +kubebuilder:scaffold:scheme

	close(done)
}, 120)

var _ = AfterSuite(func() {
	By("tearing down the test environment")

	err := testEnv.Stop()
	Expect(err).ToNot(HaveOccurred())
})
