using MongoDB.Driver;
using KubernetesToDo.Api.Models;
using MongoDB.Bson;

namespace KubernetesToDo.Api.Services;

public class TodoService
{
    private readonly IMongoCollection<TodoItem> _col;

    public TodoService(IMongoDatabase database)
    {
        _col = database.GetCollection<TodoItem>("todos");
    }

    public async Task<List<TodoItem>> GetAsync() => await _col.Find(_ => true).SortByDescending(t => t.CreatedAt).ToListAsync();

    public async Task<TodoItem?> GetAsync(string id)
    {
        return await _col.Find(t => t.Id == id).FirstOrDefaultAsync();
    }

    public async Task<TodoItem> CreateAsync(TodoItem item)
    {
        await _col.InsertOneAsync(item);
        return item;
    }

    public async Task<bool> UpdateAsync(string id, TodoItem updated)
    {
        var replaceResult = await _col.ReplaceOneAsync(t => t.Id == id, updated);
        return replaceResult.IsAcknowledged && replaceResult.ModifiedCount > 0;
    }

    public async Task<bool> RemoveAsync(string id)
    {
        var res = await _col.DeleteOneAsync(t => t.Id == id);
        return res.IsAcknowledged && res.DeletedCount > 0;
    }

    public async Task<bool> MarkCompleteAsync(string id, bool isCompleted)
    {
        var update = Builders<TodoItem>.Update.Set(t => t.IsCompleted, isCompleted);
        var res = await _col.UpdateOneAsync(t => t.Id == id, update);
        return res.IsAcknowledged && res.ModifiedCount > 0;
    }
}
