package e2e

import (
	"fmt"
	"os"

	"github.com/integr8ly/integreatly-operator/test/common"
	. "github.com/onsi/ginkgo"
)

var _ = Describe("CRO", func() {

	var (
		restConfig = cfg
		t          = GinkgoT()
	)

	BeforeEach(func() {
		restConfig = cfg
		t = GinkgoT()
	})

	RunTests := func() {

		// get all automated tests
		tests := []common.Tests{
			{
				Type:      "ALL TESTS",
				TestCases: common.ALL_TESTS,
			},
			{
				Type:      fmt.Sprintf("%s Openshift Blob Storage", t, f, ctx),
				TestCases: common.GetHappyPathTestCases(installType),
			},
			{
				Type:      fmt.Sprintf("%s IDP BASED", installType),
				TestCases: common.GetIDPBasedTestCases(installType),
			},
			{
				Type:      fmt.Sprintf("%s Functional", installType),
				TestCases: FUNCTIONAL_TESTS,
			},
			{
				Type:      "SCALABILITY TESTS",
				TestCases: common.SCALABILITY_TESTS,
			},
			{
				Type:      "FAILURE TESTS",
				TestCases: common.FAILURE_TESTS,
			},
		}

		for _, test := range tests {
			Context(test.Type, func() {
				for _, testCase := range test.TestCases {
					currentTest := testCase
					It(currentTest.Description, func() {
						testingContext, err := common.NewTestingContext(restConfig)
						if err != nil {
							t.Fatal("failed to create testing context", err)
						}
						currentTest.Test(t, testingContext)
					})
				}
			})
		}

	}

	RunTests()

})
