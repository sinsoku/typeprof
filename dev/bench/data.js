window.BENCHMARK_DATA = {
  "lastUpdate": 1790073090746,
  "repoUrl": "https://github.com/sinsoku/typeprof",
  "entries": {
    "Analysis time": [
      {
        "commit": {
          "author": {
            "email": "sinsoku.listy@gmail.com",
            "name": "Takumi Shotoku",
            "username": "sinsoku"
          },
          "committer": {
            "email": "sinsoku.listy@gmail.com",
            "name": "Takumi Shotoku",
            "username": "sinsoku"
          },
          "distinct": true,
          "id": "2d353c5aded27dd19ce16cde4cbaf3315e2e6162",
          "message": "Verify the gh-pages push",
          "timestamp": "2026-08-30T10:53:57+09:00",
          "tree_id": "8144ab9269952e7cbb2e611f77ceb0ff8ce967ca",
          "url": "https://github.com/sinsoku/typeprof/commit/2d353c5aded27dd19ce16cde4cbaf3315e2e6162"
        },
        "date": 1788054972796,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "typeprof",
            "value": 4.46,
            "unit": "s"
          },
          {
            "name": "optcarrot",
            "value": 3.14,
            "unit": "s"
          },
          {
            "name": "rubygems.org",
            "value": 19.28,
            "unit": "s"
          },
          {
            "name": "redmine",
            "value": 81.88,
            "unit": "s"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "sinsoku.listy@gmail.com",
            "name": "Takumi Shotoku",
            "username": "sinsoku"
          },
          "committer": {
            "email": "sinsoku.listy@gmail.com",
            "name": "Takumi Shotoku",
            "username": "sinsoku"
          },
          "distinct": false,
          "id": "b6089c5c1813c51ea8d94dc0d7bfb67db1e6df1c",
          "message": "Analyze the benchmark projects with the RBS of their gems\n\nThe projects were analyzed with `--no-collection`, so every library\nthey use was untyped. Installing their gems and the matching RBS makes\nthe numbers reflect the way TypeProf is used on a real project, at the\ncost of a longer analysis.\n\nThe gem versions and the RBS collection are pinned to a fixed date so\nthat runs stay comparable. Bundler's cooldown does the pinning, which\navoids keeping a lockfile per project in this repository.",
          "timestamp": "2026-09-22T17:31:38+09:00",
          "tree_id": "b6e54365d16d98cec75c098ca1187deca4215329",
          "url": "https://github.com/sinsoku/typeprof/commit/b6089c5c1813c51ea8d94dc0d7bfb67db1e6df1c"
        },
        "date": 1790073088013,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "typeprof",
            "value": 6.32,
            "unit": "s"
          },
          {
            "name": "optcarrot",
            "value": 4.93,
            "unit": "s"
          },
          {
            "name": "rubygems.org",
            "value": 121.92,
            "unit": "s"
          },
          {
            "name": "redmine",
            "value": 210.21,
            "unit": "s"
          }
        ]
      }
    ],
    "Type coverage": [
      {
        "commit": {
          "author": {
            "email": "sinsoku.listy@gmail.com",
            "name": "Takumi Shotoku",
            "username": "sinsoku"
          },
          "committer": {
            "email": "sinsoku.listy@gmail.com",
            "name": "Takumi Shotoku",
            "username": "sinsoku"
          },
          "distinct": true,
          "id": "2d353c5aded27dd19ce16cde4cbaf3315e2e6162",
          "message": "Verify the gh-pages push",
          "timestamp": "2026-08-30T10:53:57+09:00",
          "tree_id": "8144ab9269952e7cbb2e611f77ceb0ff8ce967ca",
          "url": "https://github.com/sinsoku/typeprof/commit/2d353c5aded27dd19ce16cde4cbaf3315e2e6162"
        },
        "date": 1788054974468,
        "tool": "customBiggerIsBetter",
        "benches": [
          {
            "name": "typeprof",
            "value": 78.56,
            "unit": "%"
          },
          {
            "name": "optcarrot",
            "value": 86.49,
            "unit": "%"
          },
          {
            "name": "rubygems.org",
            "value": 31.37,
            "unit": "%"
          },
          {
            "name": "redmine",
            "value": 35.58,
            "unit": "%"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "sinsoku.listy@gmail.com",
            "name": "Takumi Shotoku",
            "username": "sinsoku"
          },
          "committer": {
            "email": "sinsoku.listy@gmail.com",
            "name": "Takumi Shotoku",
            "username": "sinsoku"
          },
          "distinct": false,
          "id": "b6089c5c1813c51ea8d94dc0d7bfb67db1e6df1c",
          "message": "Analyze the benchmark projects with the RBS of their gems\n\nThe projects were analyzed with `--no-collection`, so every library\nthey use was untyped. Installing their gems and the matching RBS makes\nthe numbers reflect the way TypeProf is used on a real project, at the\ncost of a longer analysis.\n\nThe gem versions and the RBS collection are pinned to a fixed date so\nthat runs stay comparable. Bundler's cooldown does the pinning, which\navoids keeping a lockfile per project in this repository.",
          "timestamp": "2026-09-22T17:31:38+09:00",
          "tree_id": "b6e54365d16d98cec75c098ca1187deca4215329",
          "url": "https://github.com/sinsoku/typeprof/commit/b6089c5c1813c51ea8d94dc0d7bfb67db1e6df1c"
        },
        "date": 1790073090382,
        "tool": "customBiggerIsBetter",
        "benches": [
          {
            "name": "typeprof",
            "value": 82.68,
            "unit": "%"
          },
          {
            "name": "optcarrot",
            "value": 88.02,
            "unit": "%"
          },
          {
            "name": "rubygems.org",
            "value": 35.75,
            "unit": "%"
          },
          {
            "name": "redmine",
            "value": 46.99,
            "unit": "%"
          }
        ]
      }
    ]
  }
}