require "rails_helper"

describe Linter::Jshint do
  describe ".can_lint?" do
    context "given a .js file" do
      it "returns true" do
        result = Linter::Jshint.can_lint?("foo.js")

        expect(result).to eq true
      end
    end

    context "given a .js.coffee file" do
      it "returns false" do
        result = Linter::Jshint.can_lint?("foo.js.coffee")

        expect(result).to eq false
      end
    end

    context "given a non-js file" do
      it "returns false" do
        result = Linter::Jshint.can_lint?("foo.rb")

        expect(result).to eq false
      end
    end
  end

  describe "#file_included?" do
    context "file is in excluded file list" do
      it "returns false" do
        linter = build_linter(nil, Linter::Jshint::IGNORE_FILENAME => "foo.js")
        commit_file = double("CommitFile", filename: "foo.js")

        expect(linter.file_included?(commit_file)).to eq false
      end
    end

    context "file is not excluded" do
      it "returns true" do
        linter = build_linter(nil, Linter::Jshint::IGNORE_FILENAME => "foo.js")
        commit_file = double("CommitFile", filename: "bar.js")

        expect(linter.file_included?(commit_file)).to eq true
      end

      it "matches a glob pattern" do
        linter = build_linter(
          nil,
          Linter::Jshint::IGNORE_FILENAME => "app/javascripts/*.js\nvendor/*",
        )
        commit_file1 = double(
          "CommitFile",
          filename: "app/javascripts/bar.js",
        )
        commit_file2 = double(
          "CommitFile",
          filename: "vendor/javascripts/foo.js",
        )

        expect(linter.file_included?(commit_file1)).to be false
        expect(linter.file_included?(commit_file2)).to be false
      end
    end
  end

  describe "#file_review" do
    it "returns a saved and incomplete file review" do
      stub_owner_hound_config(instance_double("HoundConfig", content: {}))
      commit_file = build_commit_file(filename: "lib/a.js")
      linter = build_linter

      result = linter.file_review(commit_file)

      expect(result).to be_persisted
      expect(result).not_to be_completed
    end

    it "schedules a review job" do
      stub_owner_hound_config(instance_double("HoundConfig", content: {}))
      build = build(:build, commit_sha: "foo", pull_request_number: 123)
      commit_file = build_commit_file(filename: "lib/a.js")
      allow(Resque).to receive(:enqueue)
      linter = build_linter(build)

      linter.file_review(commit_file)

      expect(Resque).to have_received(:enqueue).with(
        JshintReviewJob,
        filename: commit_file.filename,
        commit_sha: build.commit_sha,
        linter_name: "jshint",
        pull_request_number: build.pull_request_number,
        patch: commit_file.patch,
        content: commit_file.content,
        config: "{}",
      )
    end

    context "when there is an owner level config enabled" do
      it "schedules a review job with the owner's config" do
        build = build(:build, commit_sha: "foo", pull_request_number: 123)
        stub_owner_hound_config(
          HoundConfig.new(
            stubbed_commit(stub_config_files('{"asi": false, "maxlen": 50}')),
          )
        )
        linter = build_linter(build, stub_config_files('{"asi": true}')
        )
        commit_file = build_commit_file(filename: "lib/a.js")

        allow(Resque).to receive(:enqueue)

        linter.file_review(commit_file)

        expect(Resque).to have_received(:enqueue).with(
          JshintReviewJob,
          commit_sha: build.commit_sha,
          config: '{"asi":true,"maxlen":50}',
          content: commit_file.content,
          filename: commit_file.filename,
          linter_name: "jshint",
          patch: commit_file.patch,
          pull_request_number: build.pull_request_number,
        )
      end
    end
  end

  def stub_config_files(config_content)
    {
      ".jshintrc" => config_content,
      ".hound.yml" => <<~CON,
        "jshint":
          "config_file": ".jshintrc"
      CON
    }
  end

  def stub_owner_hound_config(config)
    allow(BuildOwnerHoundConfig).to receive(:run).and_return(config)
  end
end
