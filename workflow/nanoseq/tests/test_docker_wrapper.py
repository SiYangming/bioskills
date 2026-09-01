import unittest
import workflow.scripts.docker_wrapper as dw

class TestDockerWrapper(unittest.TestCase):
    def test_command_building(self):
        image = "quay.io/biocontainers/samtools:1.23--h96c455f_0"
        volumes = ["/host:/host"]
        workdir = "/host"
        cmd = ["bash","-lc","echo","ok"]
        built = dw.build_docker_command(image, volumes, workdir, cmd)
        self.assertEqual(built[0], "docker")
        self.assertIn(image, built)
        self.assertIn("-v", built)
        self.assertIn("/host:/host", built)
        self.assertIn("-w", built)
        self.assertIn("/host", built)

if __name__ == "__main__":
    unittest.main()
