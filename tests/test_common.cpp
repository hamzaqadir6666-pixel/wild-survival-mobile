#include "../src/common/path_ftp_utils.h"
#include "../src/common/pack_format.h"

#include <cassert>
#include <iostream>
#include <random>

int main() {
    using namespace aero;

    // 1. FTP URL parsing tests
    {
        auto u1 = ParseFtpUrl(L"ftp://ftp.dlptest.com");
        assert(u1.valid);
        assert(!u1.useFtps);
        assert(u1.host == L"ftp.dlptest.com");
        assert(u1.port == 21);
        assert(u1.username == L"anonymous");
        assert(u1.remotePath == L"/");
    }
    {
        auto u2 = ParseFtpUrl(L"ftp://dlpuser%40dlptest.com:My%3APass@ftp.dlptest.com:2121/pub/releases/");
        assert(u2.valid);
        assert(u2.explicitCredentials);
        assert(u2.username == L"dlpuser@dlptest.com");
        assert(u2.password == L"My:Pass");
        assert(u2.host == L"ftp.dlptest.com");
        assert(u2.port == 2121);
        assert(u2.remotePath == L"/pub/releases");

        std::wstring rebuiltSafe = BuildFtpUrl(u2, false);
        assert(rebuiltSafe == L"ftp://dlpuser%40dlptest.com@ftp.dlptest.com:2121/pub/releases");

        std::wstring rebuiltFull = BuildFtpUrl(u2, true);
        auto u2Round = ParseFtpUrl(rebuiltFull);
        assert(u2Round.valid);
        assert(u2Round.username == u2.username);
        assert(u2Round.password == u2.password);
        assert(u2Round.host == u2.host);
        assert(u2Round.port == u2.port);
        assert(u2Round.remotePath == u2.remotePath);
    }

    // 2. Breadcrumb tests
    {
        auto bcLocal = BuildBreadcrumbs(L"C:\\Users\\Alice\\Documents");
        assert(bcLocal.size() == 5);
        assert(bcLocal[0].label == L"Computer" && bcLocal[0].target == L"computer://");
        assert(bcLocal[1].target == L"C:\\");
        assert(bcLocal[4].label == L"Documents" && bcLocal[4].target == L"C:\\Users\\Alice\\Documents");

        auto bcFtp = BuildBreadcrumbs(L"ftp://user:pw@192.168.1.20/var/www/html");
        assert(bcFtp.size() == 5);
        assert(bcFtp[0].label == L"Computer");
        assert(bcFtp[1].label == L"FTP (192.168.1.20)");
        assert(bcFtp[4].label == L"html");
        assert(ParentFtpPath(L"/var/www/html") == L"/var/www");
        assert(ParentFtpPath(L"/var") == L"/");
        assert(ParentFtpPath(L"/") == L"/");
    }

    // 3. Secret obfuscation roundtrip
    {
        std::wstring pw = L"S3cr3t!P@ss#2026";
        std::wstring enc = ObfuscateSecret(pw);
        assert(enc != pw && !enc.empty());
        assert(DeobfuscateSecret(enc) == pw);
    }

    // 4. AeroPak LZSS + CRC32 archive tests
    {
        std::vector<uint8_t> peSim(180000);
        std::mt19937 rng(42);
        for (size_t i = 0; i < peSim.size(); ++i) {
            // Mix structured repetitive code-like bytes and random bytes
            if ((i % 64) < 44) {
                peSim[i] = static_cast<uint8_t>((i * 7 + (i / 256)) & 0xFF);
            } else {
                peSim[i] = static_cast<uint8_t>(rng() & 0xFF);
            }
        }
        std::string readme = "Windows 7 Aero Explorer for Windows 10\r\nBuilt-in FTP Support.\r\n";
        std::vector<uint8_t> readmeBytes(readme.begin(), readme.end());

        std::vector<aeropak::PackedEntry> inputs = {
            { "AeroExplorer.exe", 0, 0, peSim },
            { "README.txt", 0, 0, readmeBytes },
            { "empty.dat", 0, 0, {} },
        };

        std::vector<uint8_t> archive = aeropak::BuildArchive(inputs);
        assert(archive.size() < peSim.size()); // Compressed smaller than input!

        std::vector<aeropak::PackedEntry> extracted;
        bool ok = aeropak::ExtractArchive(archive.data(), archive.size(), extracted);
        assert(ok);
        assert(extracted.size() == 3);
        assert(extracted[0].relativeName == "AeroExplorer.exe");
        assert(extracted[0].data == peSim);
        assert(extracted[1].relativeName == "README.txt");
        assert(extracted[1].data == readmeBytes);
        assert(extracted[2].relativeName == "empty.dat");
        assert(extracted[2].data.empty());

        // Corrupt a byte -> CRC32 / LZSS check must reject!
        archive[archive.size() / 2] ^= 0x5Au;
        std::vector<aeropak::PackedEntry> badOut;
        assert(!aeropak::ExtractArchive(archive.data(), archive.size(), badOut));
    }

    std::cout << "All common & AeroPak unit tests PASSED!\n";
    return 0;
}
