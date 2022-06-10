// Copyright 2020-2021 Dave Verwer, Sven A. Schmidt, and other contributors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.


extension Result {
    func getError() -> Error? {
        switch self {
            case .success:
                return nil
            case .failure(let error):
                return error
        }
    }
}


extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do {
            self = .success(try await body())
        } catch {
            self = .failure(error)
        }
    }
}


extension Result {
    func mapAsync<NewSuccess>(_ transform: (Success) async -> NewSuccess) async -> Result<NewSuccess, Failure> {
        switch self {
            case .success(let success):
                return .success(await transform(success))
            case .failure(let failure):
                return .failure(failure)
        }
    }


    func flatMapAsync<NewSuccess>(_ transform: (Success) async -> Result<NewSuccess, Failure>) async -> Result<NewSuccess, Failure> {
        switch self {
            case .success(let success):
                return await transform(success)
            case .failure(let failure):
                return .failure(failure)
        }
    }
}
