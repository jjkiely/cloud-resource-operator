package e2e

import "github.com/integr8ly/integreatly-operator/test/common"

var (
	CRO_TESTS = []common.TestCase{
		{Description: "Blob Storage", Test: OpenshiftBlobstorageBasicTest},
		{Description: "F03 - Verify AWS elasticache resources exist and are in expected state", Test: AWSElasticacheResourcesExistTest},
		{Description: "A21 - Verify AWS maintenance and backup windows", Test: CROStrategyOverrideAWSResourceTest},
		{Description: "A25 - Verify standalone RHMI VPC exists and is configured properly", Test: TestStandaloneVPCExists},
		{Description: "F04 - Verify AWS s3 blob storage resources exist", Test: TestAWSs3BlobStorageResourcesExist},
	}
)
