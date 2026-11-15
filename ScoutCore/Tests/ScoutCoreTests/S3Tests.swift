import Foundation
import Testing
@testable import ScoutCore

@Suite struct S3Tests {
    /// AWS's published example ("GET Object" in the S3 Signature Version 4 docs).
    @Test func signatureMatchesAWSExample() throws {
        var request = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!)
        request.httpMethod = "GET"
        request.setValue("bytes=0-9", forHTTPHeaderField: "Range")
        let date = try #require(ISO8601DateFormatter().date(from: "2013-05-24T00:00:00Z"))
        SigV4.sign(&request, accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
                   region: "us-east-1", date: date)
        #expect(request.value(forHTTPHeaderField: "Authorization") ==
            "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, "
            + "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, "
            + "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
    }

    /// AWS's published "GET Bucket (List Objects)" example: query parameters sorted and encoded.
    @Test func signatureWithQueryMatchesAWSExample() throws {
        var request = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/?max-keys=2&prefix=J")!)
        let date = try #require(ISO8601DateFormatter().date(from: "2013-05-24T00:00:00Z"))
        SigV4.sign(&request, accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
                   region: "us-east-1", date: date)
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasSuffix(
            "Signature=34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7") == true)
    }

    @Test func urlsArePathStyleAndEscaped() {
        let client = S3Client(config: BucketConfig(name: "R2", endpoint: "https://acct.r2.cloudflarestorage.com/",
                                                   bucket: "assets", accessKeyID: "k"), secretKey: "s")
        #expect(client.url(key: "photos/My Trip #1.jpg").absoluteString
            == "https://acct.r2.cloudflarestorage.com/assets/photos/My%20Trip%20%231.jpg")
        #expect(client.url(query: [URLQueryItem(name: "prefix", value: "a b/")]).absoluteString
            == "https://acct.r2.cloudflarestorage.com/assets/?prefix=a%20b%2F")
    }

    @Test func parsesListings() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
          <Name>assets</Name><Prefix>photos/</Prefix><KeyCount>3</KeyCount>
          <Contents><Key>photos/</Key><Size>0</Size><LastModified>2026-11-01T10:00:00.000Z</LastModified></Contents>
          <Contents><Key>photos/a.jpg</Key><Size>2048</Size><LastModified>2026-11-02T10:00:00.000Z</LastModified></Contents>
          <CommonPrefixes><Prefix>photos/2026/</Prefix></CommonPrefixes>
          <IsTruncated>true</IsTruncated><NextContinuationToken>abc==</NextContinuationToken>
        </ListBucketResult>
        """
        let listing = BucketListing.parse(Data(xml.utf8))
        #expect(listing.folders == ["photos/2026/"])
        #expect(listing.objects.map(\.key) == ["photos/a.jpg"])
        #expect(listing.objects.first?.name == "a.jpg")
        #expect(listing.objects.first?.size == 2048)
        #expect(listing.objects.first?.modified != nil)
        #expect(listing.nextToken == "abc==")
    }
}
