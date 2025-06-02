//
//  Networking.swift
//  HackatonYandex
//
//  Created by Родион Холодов on 02.06.2025.
//
import Foundation

class Networking {
    
    func uploadWavFile(fileURL: URL, completion: @escaping (Result<SpeechToTextModel, Error>) -> Void) {
        let url = URL(string: "http://127.0.0.1:8000/api/speech-to-text")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var data = Data()
        
        // Формируем тело запроса
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        
        do {
            let fileData = try Data(contentsOf: fileURL)
            data.append(fileData)
        } catch {
            completion(.failure(error))
            return
        }
        
        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = data
        
        let task = URLSession.shared.dataTask(with: request) { responseData, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let responseData = responseData else {
                completion(.failure(NSError(domain: "No response data", code: 0)))
                return
            }
            
            do {
                let model = try JSONDecoder().decode(SpeechToTextModel.self, from: responseData)
                completion(.success(model))
            } catch {
                print("Decode error: \(error.localizedDescription)")
                if let raw = String(data: responseData, encoding: .utf8) {
                    print("Raw response: \(raw)")
                }
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    /// Начать запись в реальном времени
    func startRealtimeRecording(completion: @escaping (Result<RealtimeResponseModel, Error>) -> Void) {
        let url = URL(string: "http://127.0.0.1:8000/api/realtime/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: 0)))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(RealtimeResponseModel.self, from: data)
                completion(.success(response))
            } catch {
                print("Decode error: \(error.localizedDescription)")
                if let raw = String(data: data, encoding: .utf8) {
                    print("Raw response: \(raw)")
                }
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    /// Остановить запись в реальном времени
    func stopRealtimeRecording(completion: @escaping (Result<RealtimeResponseModel, Error>) -> Void) {
        let url = URL(string: "http://127.0.0.1:8000/api/realtime/stop")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: 0)))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(RealtimeResponseModel.self, from: data)
                completion(.success(response))
            } catch {
                print("Decode error: \(error.localizedDescription)")
                if let raw = String(data: data, encoding: .utf8) {
                    print("Raw response: \(raw)")
                }
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
}
